-- ============================================================
-- DEEP DIVE IS — QUERIES CANÓNICAS
-- Base: RP_GOLD_DB_PROD.RESTAURANTS_HUNTING
-- Produce los 4 bloques de datos para el HTML del deep dive:
--   project · country · aging (proyecto×país×aging) · buckets
-- Parámetros: :quarter (ej 'Q2')  |  :lw = MAX(WEEK_DATE) del funnel
-- ============================================================


-- ─────────────────────────────────────────────────────────────
-- PASO 0 — Obtener LW (ejecutar siempre primero)
-- ─────────────────────────────────────────────────────────────
SELECT MAX(WEEK_DATE) AS last_week
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
WHERE Q = :quarter;


-- ─────────────────────────────────────────────────────────────
-- QUERY PRINCIPAL — todos los bloques en una sola ejecución
-- Reemplazar :quarter y :lw con los valores reales
-- ─────────────────────────────────────────────────────────────

WITH hunter_base AS (
  -- Granularidad: hunter × proyecto × aging × país
  -- prod_target = target de productividad para esa celda (aging × país × proyecto × semana)
  SELECT
    f.PROYECTO_AGRUPADO                                                    AS proyecto,
    f.AGING_CATEGORY_FINAL                                                 AS aging,
    f.COUNTRY,
    f.HUNTER_EMAIL,
    SUM(f.DIAS_TRABAJADOS)                                                 AS dias,
    SUM(f.STORES_TOTALES)                                                  AS stores,
    AVG(t.TARGET)                                                          AS prod_target
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD f
  LEFT JOIN RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD t
         ON t.WEEK       = f.WEEK_DATE
        AND t.COUNTRY    = f.COUNTRY
        AND t.PROYECTO   = f.PROYECTO_AGRUPADO
        AND UPPER(TRIM(t.AGING)) = UPPER(TRIM(
              CASE f.AGING_CATEGORY_FINAL
                WHEN 'New Entry' THEN '01 - New Entry'
                WHEN 'Junior'    THEN '02 - Junior'
                WHEN 'Senior'    THEN '03 - Senior'
              END))
        AND t.TIPO_TARGET = 'PRODUCTIVIDAD'
        AND t.Q = :quarter
  WHERE f.Q = :quarter
    AND f.WEEK_DATE = :lw
  GROUP BY 1, 2, 3, 4
),

hunter_calc AS (
  -- Agrega métricas derivadas por hunter
  SELECT *,
    CASE WHEN dias > 0 THEN stores / dias ELSE 0 END           AS prod_real,
    dias * COALESCE(prod_target, 0)                            AS stores_tg_hunter,
    -- Bucket de performance (5 niveles para IS)
    CASE
      WHEN stores = 0                                          THEN '00 stores'
      WHEN COALESCE(prod_target, 0) > 0
       AND stores / NULLIF(dias, 0) < 0.5 * prod_target        THEN '<50% target prod'
      WHEN COALESCE(prod_target, 0) > 0
       AND stores / NULLIF(dias, 0) < 0.8 * prod_target        THEN '50-80% target prod'
      WHEN COALESCE(prod_target, 0) > 0
       AND stores / NULLIF(dias, 0) < prod_target              THEN '80-100% target prod'
      ELSE                                                          '>= target prod'
    END                                                        AS bucket
  FROM hunter_base
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE A — Por proyecto (INBOUND / OUTBOUND)
-- ─────────────────────────────────────────────────────────────
project_agg AS (
  SELECT
    proyecto,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores_real,
    ROUND(SUM(stores_tg_hunter), 0)                                        AS stores_tg,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE B — Por proyecto × país
-- ─────────────────────────────────────────────────────────────
country_agg AS (
  SELECT
    proyecto,
    COUNTRY                                                                AS country,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1, 2
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE C — Por proyecto × país × aging (top arrastres)
-- ─────────────────────────────────────────────────────────────
aging_agg AS (
  SELECT
    proyecto,
    COUNTRY                                                                AS country,
    aging,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1, 2, 3
),


-- ─────────────────────────────────────────────────────────────
-- BLOQUE D — Buckets de performance por proyecto
-- ─────────────────────────────────────────────────────────────
bucket_agg AS (
  SELECT
    proyecto,
    bucket,
    COUNT(DISTINCT HUNTER_EMAIL)                                           AS hunters,
    SUM(dias)                                                              AS dias,
    SUM(stores)                                                            AS stores,
    ROUND(SUM(stores) / NULLIF(SUM(dias), 0), 3)                           AS prod_real,
    ROUND(SUM(dias * COALESCE(prod_target,0)) / NULLIF(SUM(dias), 0), 3)   AS prod_target,
    ROUND(SUM(stores) - SUM(stores_tg_hunter), 0)                          AS impacto
  FROM hunter_calc
  GROUP BY 1, 2
)


-- ─────────────────────────────────────────────────────────────
-- EJECUCIÓN: correr cada SELECT por separado y armar el DATA JSON
-- ─────────────────────────────────────────────────────────────

-- A) Proyecto
SELECT * FROM project_agg ORDER BY impacto;

-- B) País (agregar por proyecto)
SELECT * FROM country_agg ORDER BY proyecto, impacto;

-- C) Aging × País (top 12-15 por impacto para los gráficos)
SELECT * FROM aging_agg ORDER BY impacto;

-- D) Buckets (orden: 00 stores, <50%, 50-80%, 80-100%, >= target)
SELECT * FROM bucket_agg ORDER BY proyecto,
  CASE bucket
    WHEN '00 stores'           THEN 1
    WHEN '<50% target prod'    THEN 2
    WHEN '50-80% target prod'  THEN 3
    WHEN '80-100% target prod' THEN 4
    ELSE                            5
  END;
