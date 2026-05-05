-- nuevo_framing_q2 / queries.sql
-- Param: :quarter

-- =========================================================
-- 1) week_axis
-- =========================================================
SELECT DISTINCT WEEK
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
WHERE Q = :quarter
ORDER BY WEEK;

-- =========================================================
-- 2) main_metrics_top_query
-- =========================================================
WITH elc AS (
    SELECT
        WEEK,
        TYPE AS METRIC,
        SUM(TOTAL_STORES) AS VALUE
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TYPE IN ('AVAILABLE', 'ACTIVE')
    GROUP BY 1,2
)
SELECT
    WEEK,
    SUM(CASE WHEN METRIC = 'AVAILABLE' THEN VALUE ELSE 0 END) AS total_available_stores,
    SUM(CASE WHEN METRIC = 'ACTIVE' THEN VALUE ELSE 0 END) AS total_active_stores,
    SUM(CASE WHEN METRIC = 'ACTIVE' THEN VALUE ELSE 0 END)
      / NULLIF(SUM(CASE WHEN METRIC = 'AVAILABLE' THEN VALUE ELSE 0 END), 0) AS activation_rate_pct
FROM elc
GROUP BY 1
ORDER BY 1;

-- =========================================================
-- 3) main_metrics_bottom_query
-- =========================================================
WITH elc AS (
    SELECT
        WEEK,
        TYPE AS METRIC,
        SUM(TOTAL_STORES) AS VALUE
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TYPE IN ('AVAILABLE', 'ACTIVE')
    GROUP BY 1,2
)
SELECT
    WEEK,
    SUM(CASE WHEN METRIC = 'AVAILABLE' THEN VALUE ELSE 0 END) AS new_available_stores,
    SUM(CASE WHEN METRIC = 'ACTIVE' THEN VALUE ELSE 0 END) AS new_active_stores,
    SUM(CASE WHEN METRIC = 'ACTIVE' THEN VALUE ELSE 0 END)
      / NULLIF(SUM(CASE WHEN METRIC = 'AVAILABLE' THEN VALUE ELSE 0 END), 0) AS new_inflow_active_rate_pct
FROM elc
GROUP BY 1
ORDER BY 1;

-- =========================================================
-- 4) hunting_query
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN TOTAL_STORES ELSE 0 END) AS total_new_available_stores_hunting,
        SUM(CASE WHEN TYPE = 'CREATED' THEN TOTAL_STORES ELSE 0 END) AS total_hunting_store_created
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'HUNTING'
      AND CHANNEL_GROUP = 'HUNTING'
      AND TYPE IN ('CREATED', 'AVAILABLE')
    GROUP BY 1
),
elc_target AS (
    SELECT
        WEEK,
        SUM(TARGET) AS target_total_new_available_stores_hunting
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'HUNTING'
      AND CHANNEL_GROUP = 'HUNTING'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY 1
),
ht_days AS (
    SELECT
        COUNTRY,
        WEEK_DATE AS WEEK,
        CASE
            WHEN AGING_CATEGORY_FINAL = 'New Entry' THEN '01 - new entry'
            WHEN AGING_CATEGORY_FINAL = 'Junior' THEN '02 - junior'
            WHEN AGING_CATEGORY_FINAL = 'Senior' THEN '03 - senior'
        END AS AGING,
        HUNTER_EMAIL,
        SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
    WHERE Q = :quarter
      AND HC = 1
    GROUP BY 1,2,3,4
),
ht_target_prod AS (
    SELECT
        COUNTRY,
        WEEK,
        AGING,
        AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD
    WHERE Q = :quarter
      AND TIPO_TARGET = 'PRODUCTIVIDAD'
    GROUP BY 1,2,3
),
ht_calc_target AS (
    SELECT
        d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_hunting_store_created,
        SUM(d.dias_trabajados_reales) AS dias_trabajados_reales_total
    FROM ht_days d
    JOIN ht_target_prod t
      ON d.COUNTRY = t.COUNTRY
     AND d.WEEK = t.WEEK
     AND d.AGING = t.AGING
    GROUP BY 1
),
ht_actual AS (
    SELECT
        WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END) AS total_hunting_headcount,
        COUNT(DISTINCT CASE WHEN HC = 1 AND AGING_CATEGORY_FINAL = 'Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END),0) AS pct_hunters_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS),0) AS total_hunting_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
    WHERE Q = :quarter
    GROUP BY 1
),
ht_hc_target AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END) AS target_hunting_headcount,
        SUM(CASE WHEN TIPO_TARGET = 'HC' AND AGING = '03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END),0) AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD
    WHERE Q = :quarter
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ha.WEEK, hc.WEEK, tc.WEEK) AS WEEK,
    ea.total_new_available_stores_hunting,
    et.target_total_new_available_stores_hunting,
    ea.total_hunting_store_created,
    tc.target_hunting_store_created,
    ha.total_hunting_productivity,
    tc.target_hunting_store_created / NULLIF(tc.dias_trabajados_reales_total,0) AS target_hunting_productivity,
    ha.total_hunting_headcount,
    hc.target_hunting_headcount,
    ha.pct_hunters_old,
    hc.pct_target_hc_old
FROM elc_actual ea
FULL OUTER JOIN elc_target et
  ON ea.WEEK = et.WEEK
FULL OUTER JOIN ht_actual ha
  ON COALESCE(ea.WEEK, et.WEEK) = ha.WEEK
FULL OUTER JOIN ht_hc_target hc
  ON COALESCE(ea.WEEK, et.WEEK, ha.WEEK) = hc.WEEK
FULL OUTER JOIN ht_calc_target tc
  ON COALESCE(ea.WEEK, et.WEEK, ha.WEEK, hc.WEEK) = tc.WEEK
ORDER BY 1;

-- =========================================================
-- 5) inside_sales_outbound_query
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN TOTAL_STORES ELSE 0 END) AS total_new_available_stores_is_outbound,
        SUM(CASE WHEN TYPE = 'CREATED' THEN TOTAL_STORES ELSE 0 END) AS total_is_outbound_store_created
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES OUTBOUND'
      AND TYPE IN ('CREATED', 'AVAILABLE')
    GROUP BY 1
),
elc_target AS (
    SELECT
        WEEK,
        SUM(TARGET) AS target_total_new_available_stores_is_outbound
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES OUTBOUND'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY 1
),
is_days AS (
    SELECT
        COUNTRY,
        WEEK_DATE AS WEEK,
        PROYECTO,
        CASE
            WHEN AGING_CATEGORY_FINAL = 'New Entry' THEN '01 - new entry'
            WHEN AGING_CATEGORY_FINAL = 'Junior' THEN '02 - junior'
            WHEN AGING_CATEGORY_FINAL = 'Senior' THEN '03 - senior'
        END AS AGING,
        HUNTER_EMAIL,
        SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter
      AND HC = 1
      AND PROYECTO = 'OUTBOUND'
    GROUP BY 1,2,3,4,5
),
is_target_prod AS (
    SELECT
        COUNTRY,
        WEEK,
        PROYECTO,
        AGING,
        AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter
      AND TIPO_TARGET = 'PRODUCTIVIDAD'
      AND PROYECTO = 'OUTBOUND'
    GROUP BY 1,2,3,4
),
is_calc_target AS (
    SELECT
        d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_is_outbound_store_created,
        SUM(d.dias_trabajados_reales) AS dias_trabajados_reales_total
    FROM is_days d
    JOIN is_target_prod t
      ON d.COUNTRY = t.COUNTRY
     AND d.WEEK = t.WEEK
     AND d.PROYECTO = t.PROYECTO
     AND d.AGING = t.AGING
    GROUP BY 1
),
is_actual AS (
    SELECT
        WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END) AS total_is_outbound_headcount,
        COUNT(DISTINCT CASE WHEN HC = 1 AND AGING_CATEGORY_FINAL = 'Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END),0) AS pct_agents_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS),0) AS total_is_outbound_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter
      AND PROYECTO = 'OUTBOUND'
    GROUP BY 1
),
is_hc_target AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END) AS target_is_outbound_headcount,
        SUM(CASE WHEN TIPO_TARGET = 'HC' AND AGING = '03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END),0) AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter
      AND PROYECTO = 'OUTBOUND'
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK, ic.WEEK) AS WEEK,
    ea.total_new_available_stores_is_outbound,
    et.target_total_new_available_stores_is_outbound,
    ea.total_is_outbound_store_created,
    ic.target_is_outbound_store_created,
    ia.total_is_outbound_productivity,
    ic.target_is_outbound_store_created / NULLIF(ic.dias_trabajados_reales_total,0) AS target_is_outbound_productivity,
    ia.total_is_outbound_headcount,
    ih.target_is_outbound_headcount,
    ia.pct_agents_old,
    ih.pct_target_hc_old
FROM elc_actual ea
FULL OUTER JOIN elc_target et
  ON ea.WEEK = et.WEEK
FULL OUTER JOIN is_actual ia
  ON COALESCE(ea.WEEK, et.WEEK) = ia.WEEK
FULL OUTER JOIN is_hc_target ih
  ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK) = ih.WEEK
FULL OUTER JOIN is_calc_target ic
  ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK) = ic.WEEK
ORDER BY 1;

-- =========================================================
-- 6) inside_sales_inbound_query
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN TOTAL_STORES ELSE 0 END) AS total_new_available_stores_is_inbound,
        SUM(CASE WHEN TYPE = 'CREATED' THEN TOTAL_STORES ELSE 0 END) AS total_is_inbound_store_created
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES INBOUND'
      AND TYPE IN ('CREATED', 'AVAILABLE')
    GROUP BY 1
),
elc_target AS (
    SELECT
        WEEK,
        SUM(TARGET) AS target_total_new_available_stores_is_inbound
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES INBOUND'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY 1
),
is_days AS (
    SELECT
        COUNTRY,
        WEEK_DATE AS WEEK,
        PROYECTO,
        CASE
            WHEN AGING_CATEGORY_FINAL = 'New Entry' THEN '01 - new entry'
            WHEN AGING_CATEGORY_FINAL = 'Junior' THEN '02 - junior'
            WHEN AGING_CATEGORY_FINAL = 'Senior' THEN '03 - senior'
        END AS AGING,
        HUNTER_EMAIL,
        SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter
      AND HC = 1
      AND PROYECTO = 'INBOUND'
    GROUP BY 1,2,3,4,5
),
is_target_prod AS (
    SELECT
        COUNTRY,
        WEEK,
        PROYECTO,
        AGING,
        AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter
      AND TIPO_TARGET = 'PRODUCTIVIDAD'
      AND PROYECTO = 'INBOUND'
    GROUP BY 1,2,3,4
),
is_calc_target AS (
    SELECT
        d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_is_inbound_store_created,
        SUM(d.dias_trabajados_reales) AS dias_trabajados_reales_total
    FROM is_days d
    JOIN is_target_prod t
      ON d.COUNTRY = t.COUNTRY
     AND d.WEEK = t.WEEK
     AND d.PROYECTO = t.PROYECTO
     AND d.AGING = t.AGING
    GROUP BY 1
),
is_actual AS (
    SELECT
        WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END) AS total_is_inbound_headcount,
        COUNT(DISTINCT CASE WHEN HC = 1 AND AGING_CATEGORY_FINAL = 'Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END),0) AS pct_agents_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS),0) AS total_is_inbound_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter
      AND PROYECTO = 'INBOUND'
    GROUP BY 1
),
is_hc_target AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END) AS target_is_inbound_headcount,
        SUM(CASE WHEN TIPO_TARGET = 'HC' AND AGING = '03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END),0) AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter
      AND PROYECTO = 'INBOUND'
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK, ic.WEEK) AS WEEK,
    ea.total_new_available_stores_is_inbound,
    et.target_total_new_available_stores_is_inbound,
    ea.total_is_inbound_store_created,
    ic.target_is_inbound_store_created,
    ia.total_is_inbound_productivity,
    ic.target_is_inbound_store_created / NULLIF(ic.dias_trabajados_reales_total,0) AS target_is_inbound_productivity,
    ia.total_is_inbound_headcount,
    ih.target_is_inbound_headcount,
    ia.pct_agents_old,
    ih.pct_target_hc_old
FROM elc_actual ea
FULL OUTER JOIN elc_target et
  ON ea.WEEK = et.WEEK
FULL OUTER JOIN is_actual ia
  ON COALESCE(ea.WEEK, et.WEEK) = ia.WEEK
FULL OUTER JOIN is_hc_target ih
  ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK) = ih.WEEK
FULL OUTER JOIN is_calc_target ic
  ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK) = ic.WEEK
ORDER BY 1;

-- =========================================================
-- 7) self_onboarding_query
-- =========================================================
WITH so_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN TOTAL_STORES ELSE 0 END) AS total_new_available_stores_self_onboarding
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'SELF-ONBOARDING'
      AND CHANNEL_GROUP = 'SELF-ONBOARDING'
      AND TYPE = 'AVAILABLE'
    GROUP BY 1
),
so_target AS (
    SELECT
        WEEK,
        SUM(TARGET) AS target_total_new_available_stores_self_onboarding
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'SELF-ONBOARDING'
      AND CHANNEL_GROUP = 'SELF-ONBOARDING'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY 1
)
SELECT
    COALESCE(a.WEEK, t.WEEK) AS WEEK,
    a.total_new_available_stores_self_onboarding,
    t.target_total_new_available_stores_self_onboarding
FROM so_actual a
FULL OUTER JOIN so_target t
  ON a.WEEK = t.WEEK
ORDER BY 1;

-- =========================================================
-- 8) brand_expansion_query
-- =========================================================
WITH be_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN TOTAL_STORES ELSE 0 END) AS total_new_available_stores_brand_expansion,
        SUM(CASE WHEN TYPE = 'CREATED' THEN TOTAL_STORES ELSE 0 END) AS total_brand_expansion_store_created
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'BRAND EXPANSION'
      AND CHANNEL_GROUP = 'BRAND EXPANSION'
      AND TYPE IN ('AVAILABLE', 'CREATED')
    GROUP BY 1
),
be_target AS (
    SELECT
        WEEK,
        SUM(TARGET) AS target_total_new_available_stores_brand_expansion
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'BRAND EXPANSION'
      AND CHANNEL_GROUP = 'BRAND EXPANSION'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY 1
)
SELECT
    COALESCE(a.WEEK, t.WEEK) AS WEEK,
    a.total_new_available_stores_brand_expansion,
    t.target_total_new_available_stores_brand_expansion,
    a.total_brand_expansion_store_created
FROM be_actual a
FULL OUTER JOIN be_target t
  ON a.WEEK = t.WEEK
ORDER BY 1;