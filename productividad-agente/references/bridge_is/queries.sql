-- ============================================================
-- BRIDGE IS — QUERIES CANÓNICAS
-- Base: RP_GOLD_DB_PROD.RESTAURANTS_HUNTING
-- Parámetro: reemplazar :quarter por 'Q2' (u otro quarter)
--            reemplazar :week_filter por el filtro de semanas
--            según modalidad QTD o LW (ver report_spec.yaml)
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PASO 0 — Detectar semanas disponibles (ejecutar siempre primero)
-- ─────────────────────────────────────────────────────────────

-- QTD: todas las semanas con real disponible
SELECT DISTINCT WEEK_DATE
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
WHERE Q = :quarter
ORDER BY 1;

-- LW: solo la última semana
SELECT MAX(WEEK_DATE) AS last_week
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
WHERE Q = :quarter;


-- ─────────────────────────────────────────────────────────────
-- PASO 1 — Validar target (debe coincidir con SUM directo)
-- ─────────────────────────────────────────────────────────────

SELECT
    PROYECTO,
    WEEK,
    SUM(TARGET) AS stores_tg
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
WHERE Q = :quarter
  AND TIPO_TARGET = 'STORES'
  AND WEEK IN (:semanas_validas)   -- reemplazar con lista de semanas de PASO 0
GROUP BY 1, 2
ORDER BY 1, 2;


-- ─────────────────────────────────────────────────────────────
-- PASO 2 — Query principal del bridge (QTD o LW)
-- Reemplazar :week_filter según modalidad
-- ─────────────────────────────────────────────────────────────

WITH real_agg AS (
  SELECT
    f.PROYECTO_AGRUPADO AS proyecto,
    UPPER(TRIM(CASE f.AGING_CATEGORY_FINAL
      WHEN 'New Entry' THEN '01 - New Entry'
      WHEN 'Junior'    THEN '02 - Junior'
      WHEN 'Senior'    THEN '03 - Senior'
    END)) AS aging_norm,
    f.COUNTRY,
    f.WEEK_DATE AS week,
    COUNT(DISTINCT CASE WHEN f.HC = 1 THEN f.HUNTER_EMAIL END) AS hc_real,
    SUM(f.DIAS_TRABAJADOS) AS dias_real,
    SUM(f.STORES_TOTALES)  AS stores_real
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD f
  WHERE f.Q = :quarter
    AND :week_filter   -- QTD: f.WEEK_DATE <= :max_week  |  LW: f.WEEK_DATE = :last_week
  GROUP BY 1, 2, 3, 4
),

tg AS (
  SELECT
    PROYECTO,
    UPPER(TRIM(AGING)) AS aging_norm,
    COUNTRY,
    WEEK,
    SUM(CASE WHEN TIPO_TARGET = 'STORES'        THEN TARGET ELSE 0 END) AS stores_tg,
    AVG(CASE WHEN TIPO_TARGET = 'HC'            THEN TARGET END)        AS hc_tg,
    AVG(CASE WHEN TIPO_TARGET = 'PRODUCTIVIDAD' THEN TARGET END)        AS prod_tg
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
  WHERE Q = :quarter
    AND :week_filter   -- mismo filtro que real_agg
  GROUP BY 1, 2, 3, 4
),

-- FULL OUTER JOIN para capturar celdas con target sin real (ej: países sin hunters activos)
joined AS (
  SELECT
    COALESCE(r.proyecto,   t.PROYECTO)    AS proyecto,
    COALESCE(r.aging_norm, t.aging_norm)  AS aging_norm,
    COALESCE(r.COUNTRY,    t.COUNTRY)     AS country,
    COALESCE(r.week,       t.WEEK)        AS week,
    COALESCE(r.hc_real,    0)             AS hc_real,
    COALESCE(r.dias_real,  0)             AS dias_real,
    COALESCE(r.stores_real,0)             AS stores_real,
    COALESCE(t.stores_tg,  0)             AS stores_tg,
    COALESCE(t.hc_tg,      0)             AS hc_tg,
    COALESCE(t.prod_tg,    0)             AS prod_tg,
    -- dias_tg implícito por agente = stores_tg / (hc_tg × prod_tg)
    CASE WHEN COALESCE(t.hc_tg, 0) * COALESCE(t.prod_tg, 0) > 0
         THEN t.stores_tg / (t.hc_tg * t.prod_tg)
         ELSE 0
    END AS dias_tg_por_agente
  FROM real_agg r
  FULL OUTER JOIN tg t
    ON  t.PROYECTO   = r.proyecto
    AND t.aging_norm = r.aging_norm
    AND t.COUNTRY    = r.COUNTRY
    AND t.WEEK       = r.week
),

-- Agregar por proyecto (colapsar aging, país y semanas)
bp AS (
  SELECT
    proyecto,
    SUM(stores_real)                AS stores_real,
    SUM(stores_tg)                  AS stores_tg,
    SUM(dias_real)                  AS dias_real,
    SUM(hc_real)                    AS hc_real,
    SUM(hc_tg)                      AS hc_tg,
    SUM(hc_tg * dias_tg_por_agente) AS dias_tg,
    -- Prod real global
    CASE WHEN SUM(dias_real) > 0
         THEN SUM(stores_real) / SUM(dias_real)
         ELSE 0 END AS prod_real,
    -- Prod tg ponderada por dias_tg
    CASE WHEN SUM(hc_tg * dias_tg_por_agente) > 0
         THEN SUM(prod_tg * hc_tg * dias_tg_por_agente) / SUM(hc_tg * dias_tg_por_agente)
         ELSE 0 END AS prod_tg,
    -- Prod tg con mix REAL de aging (para maturity)
    CASE WHEN SUM(hc_real * dias_tg_por_agente) > 0
         THEN SUM(prod_tg * hc_real * dias_tg_por_agente) / SUM(hc_real * dias_tg_por_agente)
         ELSE 0 END AS prod_tg_mix_real
  FROM joined
  GROUP BY 1
),

calcs AS (
  SELECT *,
    CASE WHEN hc_real > 0 THEN dias_real / hc_real ELSE 0 END AS asist_real,
    CASE WHEN hc_tg   > 0 THEN dias_tg   / hc_tg   ELSE 0 END AS asist_tg
  FROM bp
)

SELECT
  proyecto,
  ROUND(stores_real, 0)            AS stores_real,
  ROUND(stores_tg, 0)              AS stores_tg,
  ROUND(stores_real - stores_tg, 0) AS desvio,

  -- ef_hc: HC puro + asistencia + residuo de cierre
  ROUND(
    (hc_real - hc_tg) * asist_tg * prod_tg
    + hc_real * (asist_real - asist_tg) * prod_tg
    + (
        (stores_real - stores_tg)
        - ((hc_real - hc_tg) * asist_tg * prod_tg + hc_real * (asist_real - asist_tg) * prod_tg)
        - hc_real * asist_real * (prod_tg_mix_real - prod_tg)
        - hc_real * asist_real * (prod_real - prod_tg_mix_real)
      )
  , 0) AS ef_hc,

  -- ef_maturity: cambio de mix aging
  ROUND(hc_real * asist_real * (prod_tg_mix_real - prod_tg), 0) AS ef_maturity,

  -- ef_prod: productividad pura (controlando mix)
  ROUND(hc_real * asist_real * (prod_real - prod_tg_mix_real), 0) AS ef_prod,

  -- Verificación de cierre (debe ser 0)
  ROUND(
    (stores_real - stores_tg)
    - (
        (hc_real - hc_tg) * asist_tg * prod_tg
        + hc_real * (asist_real - asist_tg) * prod_tg
        + (stores_real - stores_tg)
        - ((hc_real - hc_tg) * asist_tg * prod_tg + hc_real * (asist_real - asist_tg) * prod_tg)
        - hc_real * asist_real * (prod_tg_mix_real - prod_tg)
        - hc_real * asist_real * (prod_real - prod_tg_mix_real)
      )
    - hc_real * asist_real * (prod_tg_mix_real - prod_tg)
    - hc_real * asist_real * (prod_real - prod_tg_mix_real)
  , 0) AS residuo_cierre  -- debe ser 0

FROM calcs
ORDER BY proyecto;
