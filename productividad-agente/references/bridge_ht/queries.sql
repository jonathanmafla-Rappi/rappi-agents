-- ============================================================
-- BRIDGE HT — QUERIES CANÓNICAS
-- Base: RP_GOLD_DB_PROD.RESTAURANTS_HUNTING
-- Parámetro: reemplazar :quarter por 'Q2' (u otro quarter)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PASO 0 — Detectar semanas disponibles (ejecutar siempre primero)
-- ─────────────────────────────────────────────────────────────

SELECT DISTINCT WEEK_DATE
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
WHERE Q = :quarter
ORDER BY 1;

-- LW: solo la última semana
SELECT MAX(WEEK_DATE) AS last_week
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
WHERE Q = :quarter;


-- ─────────────────────────────────────────────────────────────
-- PASO 1 — Query principal del bridge (QTD o LW)
-- Reemplazar :week_list con el resultado del PASO 0
-- ─────────────────────────────────────────────────────────────

WITH weeks_valid AS (
  -- QTD: todas las semanas disponibles
  -- LW:  solo MAX(WEEK_DATE)
  SELECT DISTINCT WEEK_DATE, COUNTRY
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
  WHERE Q = :quarter
  -- Para LW agregar: AND WEEK_DATE = (SELECT MAX(WEEK_DATE) FROM ... WHERE Q = :quarter)
),

aging_map AS (
  SELECT 'New Entry' AS cat, '01 - new entry' AS aging UNION ALL
  SELECT 'Junior',           '02 - junior'           UNION ALL
  SELECT 'Senior',           '03 - senior'
),

-- Universo base: todas las combinaciones del TARGET para las semanas válidas
tg_base AS (
  SELECT
    hc_t.WEEK,
    hc_t.COUNTRY,
    hc_t.AGING,
    am.cat                                                        AS aging_cat,
    hc_t.TARGET                                                   AS tg_hc,
    prod_t.TARGET                                                 AS tg_prod,
    st.TARGET                                                     AS tg_stores,
    CASE WHEN hc_t.TARGET * prod_t.TARGET > 0
         THEN st.TARGET / (hc_t.TARGET * prod_t.TARGET)
         ELSE NULL END                                            AS dias_pp_tg
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD hc_t
  JOIN weeks_valid wv   ON hc_t.WEEK = wv.WEEK_DATE AND hc_t.COUNTRY = wv.COUNTRY
  JOIN aging_map am     ON hc_t.AGING = am.aging
  LEFT JOIN RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD prod_t
         ON prod_t.WEEK = hc_t.WEEK AND prod_t.COUNTRY = hc_t.COUNTRY
        AND prod_t.AGING = hc_t.AGING AND prod_t.TIPO_TARGET = 'PRODUCTIVIDAD'
        AND prod_t.Q = :quarter
  LEFT JOIN RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD st
         ON st.WEEK = hc_t.WEEK AND st.COUNTRY = hc_t.COUNTRY
        AND st.AGING = hc_t.AGING AND st.TIPO_TARGET = 'STORES'
        AND st.Q = :quarter
  WHERE hc_t.TIPO_TARGET = 'HC'
    AND hc_t.Q = :quarter
),

-- Real por aging/país/semana (SIN filtro HC — incluye salidos)
real_agg AS (
  SELECT
    f.WEEK_DATE,
    f.AGING_CATEGORY_FINAL,
    f.COUNTRY,
    COUNT(DISTINCT CASE WHEN f.HC = 1 THEN f.HUNTER_EMAIL END)              AS hc_real,
    SUM(f.DIAS_TRABAJADOS)                                                  AS dias_real,
    SUM(f.STORES_TOTALES)                                                   AS stores_real,
    SUM(f.STORES_TOTALES) / NULLIF(SUM(f.DIAS_TRABAJADOS), 0)              AS prod_real,
    SUM(CASE WHEN f.HC = 1 THEN f.DIAS_TRABAJADOS ELSE 0 END) /
      NULLIF(COUNT(DISTINCT CASE WHEN f.HC = 1 THEN f.HUNTER_EMAIL END),0) AS dias_pp_real
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD f
  WHERE f.Q = :quarter
    AND f.WEEK_DATE IN (SELECT WEEK_DATE FROM weeks_valid)
  GROUP BY f.WEEK_DATE, f.AGING_CATEGORY_FINAL, f.COUNTRY
),

-- JOIN: universo target como base, real como sustitución
joined AS (
  SELECT
    tb.WEEK, tb.COUNTRY, tb.AGING, tb.aging_cat,
    tb.tg_hc, tb.tg_prod, tb.tg_stores, tb.dias_pp_tg,
    COALESCE(r.hc_real,    0)            AS hc_real,
    COALESCE(r.dias_real,  0)            AS dias_real,
    COALESCE(r.stores_real,0)            AS stores_real,
    COALESCE(r.prod_real,  tb.tg_prod)   AS prod_real,     -- si sin real, usar prod_tg (no penaliza)
    COALESCE(r.dias_pp_real, tb.dias_pp_tg) AS dias_pp_real
  FROM tg_base tb
  LEFT JOIN real_agg r
         ON r.WEEK_DATE = tb.WEEK
        AND r.COUNTRY   = tb.COUNTRY
        AND r.AGING_CATEGORY_FINAL = tb.aging_cat
),

-- Totales por semana/país para cálculo de madurez
tot_tg AS (
  SELECT WEEK, COUNTRY, SUM(tg_hc) AS tg_hc_total
  FROM joined
  WHERE dias_pp_tg IS NOT NULL
  GROUP BY WEEK, COUNTRY
),
tot_real AS (
  SELECT WEEK, COUNTRY, SUM(hc_real) AS hc_real_total
  FROM joined
  GROUP BY WEEK, COUNTRY
),

-- ─── 4 MUNDOS ───────────────────────────────────────────────
-- S0: todo target
S0 AS (
  SELECT ROUND(SUM(tg_hc * dias_pp_tg * tg_prod), 1) AS v
  FROM joined WHERE dias_pp_tg IS NOT NULL
),

-- S1: prod real por aging (aísla productividad)
S1 AS (
  SELECT ROUND(SUM(tg_hc * dias_pp_tg * prod_real), 1) AS v
  FROM joined WHERE dias_pp_tg IS NOT NULL
),

-- S2m: mix aging real, volumen=target (aísla madurez)
S2m AS (
  SELECT ROUND(SUM(
    tt.tg_hc_total
    * (j.hc_real / NULLIF(tr.hc_real_total, 0))
    * j.dias_pp_tg
    * j.prod_real
  ), 1) AS v
  FROM joined j
  JOIN tot_tg  tt ON tt.WEEK = j.WEEK AND tt.COUNTRY = j.COUNTRY
  JOIN tot_real tr ON tr.WEEK = j.WEEK AND tr.COUNTRY = j.COUNTRY
  WHERE j.dias_pp_tg IS NOT NULL
),

-- S2: HC real por aging (aísla headcount)
S2 AS (
  SELECT ROUND(SUM(hc_real * dias_pp_tg * prod_real), 1) AS v
  FROM joined WHERE dias_pp_tg IS NOT NULL
),

-- S3: stores reales (total bruto, incluye HC=0)
S3 AS (
  SELECT ROUND(SUM(stores_real), 1) AS v
  FROM joined
),

-- Target oficial (para KPI card — puede diferir levemente de S0)
tg_oficial AS (
  SELECT ROUND(SUM(t.TARGET), 1) AS v
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD t
  JOIN weeks_valid wv ON t.WEEK = wv.WEEK_DATE AND t.COUNTRY = wv.COUNTRY
  WHERE t.Q = :quarter AND t.TIPO_TARGET = 'STORES'
)

SELECT
  tg.v                                    AS target_oficial,
  s0.v                                    AS target_reconstruido,
  ROUND(s1.v  - s0.v, 1)                  AS ef_prod,
  ROUND(s2m.v - s1.v, 1)                  AS ef_madurez,
  ROUND(s2.v  - s2m.v,1)                  AS ef_hc,
  ROUND(s3.v  - s2.v, 1)                  AS ef_ausencias,
  s3.v                                    AS actual,
  ROUND(s3.v  - tg.v, 1)                  AS desvio_vs_tg_oficial,
  ROUND((s3.v - tg.v) / NULLIF(tg.v,0) * 100, 1) AS desvio_pct,
  -- Verificación de cierre (debe ser 0)
  ROUND(s0.v + (s1.v-s0.v) + (s2m.v-s1.v) + (s2.v-s2m.v) + (s3.v-s2.v) - s3.v, 1) AS cierre_check
FROM S0 s0, S1 s1, S2m s2m, S2 s2, S3 s3, tg_oficial tg;
