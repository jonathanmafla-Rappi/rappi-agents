-- ============================================================
-- DEEP DIVE HT — QUERIES CANÓNICAS
-- Base: RP_GOLD_DB_PROD.RESTAURANTS_HUNTING
-- Produce los 4 bloques de datos para el HTML del deep dive:
--   aging · country · country_aging · buckets
-- Parámetros: :quarter (ej 'Q2')  |  :lw = MAX(WEEK_DATE) del funnel
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PASO 0 — Obtener LW (ejecutar siempre primero)
-- ─────────────────────────────────────────────────────────────
SELECT MAX(WEEK_DATE) AS last_week
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
WHERE Q = :quarter;


-- ─────────────────────────────────────────────────────────────
-- QUERY PRINCIPAL — todos los bloques en una sola ejecución
-- Reemplazar :quarter y :lw con los valores reales
-- ─────────────────────────────────────────────────────────────

WITH hunter_base AS (
  -- Granularidad: hunter × aging × país
  -- prod_target = target de productividad para esa celda (aging × país × semana)
  SELECT
    f.AGING_CATEGORY_FINAL                                                 AS aging,
    f.COUNTRY,
    f.HUNTER_EMAIL,
    SUM(f.DIAS_TRABAJADOS)                                                 AS dias,
    SUM(f.STORES_TOTALES)                                                  AS stores,
    AVG(t.TARGET)                                                          AS prod_target
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD f
  LEFT JOIN RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD t
         ON t.WEEK       = f.WEEK_DATE
        AND t.COUNTRY    = f.COUNTRY
        AND UPPER(TRIM(t.AGING)) = UPPER(TRIM(
              CASE f.AGING_CATEGORY_FINAL
                WHEN 'New Entry' THEN '01 - new entry'
                WHEN 'Junior'    THEN '02 - junior'
                WHEN 'Senior'    THEN '03 - senior'
              END))
        AND t.TIPO_TARGET = 'PRODUCTIVIDAD'
        AND t.Q = :quarter
  WHERE f.Q = :quarter
    AND f.WEEK_DATE = :lw
  GROUP BY 1, 2, 3
),

hunter_calc AS (
  SELECT *,
    CASE WHEN dias > 0 THEN stores / dias ELSE 0 END           AS prod_real,
    dias * COALESCE(prod_target, 0)                            AS stores_tg_hunter,
    -- Bucket de performance (3 niveles para HT — sin bucket 80-100%)
    CASE
      WHEN stores = 0                                          THEN '00 stores'
      WHEN COALESCE(prod_target, 0) > 0
       AND stores / NULLIF(dias, 0) < 0.5 * prod_target        THEN '<50% target prod'
      WHEN COALESCE(prod_target, 0) > 0
       AND stores / NULLIF(dias, 0) < prod_target              THEN '50-80% target prod'
      ELSE                                                          '>= target prod'
    END                                                        AS bucket
  FROM hunter_base
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE A — Por aging (New Entry / Junior / Senior)
-- ─────────────────────────────────────────────────────────────
aging_agg AS (
  SELECT
    aging,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores_tg_hunter), 0)                                        AS stores_tg,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE B — Por país
-- ─────────────────────────────────────────────────────────────
country_agg AS (
  SELECT
    COUNTRY                                                                AS country,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores_tg_hunter), 0)                                        AS stores_tg,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE C — Por país × aging (celdas individuales)
-- ─────────────────────────────────────────────────────────────
country_aging_agg AS (
  SELECT
    COUNTRY                                                                AS country,
    aging,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores_tg_hunter), 0)                                        AS stores_tg,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1, 2
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE D — Buckets de performance globales
-- ─────────────────────────────────────────────────────────────
bucket_agg AS (
  SELECT
    bucket,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1
),

-- KPIs globales (para la sección de tarjetas)
kpis AS (
  SELECT
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS total_gap,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    SUM(stores)                                                            AS stores_real,
    ROUND(SUM(stores_tg_hunter), 0)                                        AS stores_tg,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias
  FROM hunter_calc
)


-- ─────────────────────────────────────────────────────────────
-- EJECUCIÓN: correr cada SELECT por separado y armar el DATA JSON
-- ─────────────────────────────────────────────────────────────

-- 0) KPIs
SELECT * FROM kpis;

-- A) Aging
SELECT * FROM aging_agg ORDER BY impacto;

-- B) País
SELECT * FROM country_agg ORDER BY impacto;

-- C) País × Aging (todas las celdas)
SELECT * FROM country_aging_agg ORDER BY impacto;

-- D) Buckets globales
SELECT * FROM bucket_agg ORDER BY
  CASE bucket
    WHEN '00 stores'           THEN 1
    WHEN '<50% target prod'    THEN 2
    WHEN '50-80% target prod'  THEN 3
    ELSE                            4
  END;
