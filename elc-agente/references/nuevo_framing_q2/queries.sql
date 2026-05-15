-- nuevo_framing_q2 / queries.sql
-- Param: :quarter
-- Última actualización: 2026-05-06
--
-- NOTAS DE CAMPO:
--   ELC_FUNNEL_GOLD.METRIC es polisémico:
--     TYPE IN ('AVAILABLE','ACTIVE','CREATED','TOTAL AVAILABLE','TOTAL ACTIVE',
--              'PERFECT STORE','HANDOFF','HANDOFF_3','HANDOFF_7','HANDOFF_28',
--              'LOG_7','LOG_28','ORDER_7','ORDER_28')     → conteo de tiendas
--     TYPE IN ('AVG_DIAS_HANDOFF','AVG_DIAS_LOG','AVG_DIAS_ORDER')  → días promedio
--   NUNCA usar TOTAL_STORES — campo renombrado a METRIC.
--
-- DISTINCIÓN CLAVE:
--   TYPE = 'TOTAL AVAILABLE'  → stock acumulado total (Main Metrics stock)
--   TYPE = 'TOTAL ACTIVE'     → stock acumulado total (Main Metrics stock)
--   TYPE = 'AVAILABLE'        → New Available (flujo semanal, por canal)
--   TYPE = 'ACTIVE'           → New Active    (flujo semanal, por canal)
--
-- NET ADDS:
--   Net Available Adds(t) = TOTAL AVAILABLE(t) - TOTAL AVAILABLE(t-1)
--   Net Active Adds(t)    = TOTAL ACTIVE(t)    - TOTAL ACTIVE(t-1)
--   Se calculan con LAG en la query main_metrics_top_query.

-- =========================================================
-- 1) week_axis
-- =========================================================
SELECT DISTINCT WEEK
FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
WHERE Q = :quarter
ORDER BY WEEK;

-- =========================================================
-- 2) main_metrics_top_query
--    Total Available / Active (stock), Net Adds, Activation Rate
-- =========================================================
WITH stock AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'TOTAL AVAILABLE' THEN METRIC ELSE 0 END) AS total_available,
        SUM(CASE WHEN TYPE = 'TOTAL ACTIVE'    THEN METRIC ELSE 0 END) AS total_active,
        SUM(CASE WHEN TYPE = 'AVAILABLE'        THEN METRIC ELSE 0 END) AS new_available,
        SUM(CASE WHEN TYPE = 'ACTIVE'           THEN METRIC ELSE 0 END) AS new_active
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TYPE IN ('TOTAL AVAILABLE','TOTAL ACTIVE','AVAILABLE','ACTIVE')
    GROUP BY WEEK
)
SELECT
    WEEK,
    total_available                                                              AS total_available_stores,
    total_active                                                                 AS total_active_stores,
    new_active / NULLIF(new_available, 0)                                        AS activation_rate_pct,
    total_available - LAG(total_available) OVER (ORDER BY WEEK)                  AS net_available_adds,
    total_active    - LAG(total_active)    OVER (ORDER BY WEEK)                  AS net_active_adds
FROM stock
ORDER BY WEEK;

-- =========================================================
-- 3) main_metrics_bottom_query
--    New Available / New Active (flujo semanal, todos los canales)
-- =========================================================
WITH elc AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN METRIC ELSE 0 END) AS new_available_stores,
        SUM(CASE WHEN TYPE = 'ACTIVE'    THEN METRIC ELSE 0 END) AS new_active_stores
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TYPE IN ('AVAILABLE', 'ACTIVE')
    GROUP BY WEEK
)
SELECT
    WEEK,
    new_available_stores,
    new_active_stores,
    new_active_stores / NULLIF(new_available_stores, 0) AS new_inflow_active_rate_pct
FROM elc
ORDER BY WEEK;

-- =========================================================
-- 4) hunting_query
--    Métricas existentes + nuevas métricas de funnel
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE'     THEN METRIC ELSE 0 END) AS total_new_available_stores_hunting,
        SUM(CASE WHEN TYPE = 'CREATED'       THEN METRIC ELSE 0 END) AS total_hunting_store_created,
        -- Nuevas métricas de funnel
        SUM(CASE WHEN TYPE = 'PERFECT STORE' THEN METRIC ELSE 0 END) AS perfect_stores,
        SUM(CASE WHEN TYPE = 'HANDOFF_3'     THEN METRIC ELSE 0 END) AS handoff_3,
        SUM(CASE WHEN TYPE = 'HANDOFF_7'     THEN METRIC ELSE 0 END) AS handoff_7,
        SUM(CASE WHEN TYPE = 'HANDOFF_28'    THEN METRIC ELSE 0 END) AS handoff_28,
        SUM(CASE WHEN TYPE = 'LOG_7'         THEN METRIC ELSE 0 END) AS log_7,
        SUM(CASE WHEN TYPE = 'LOG_28'        THEN METRIC ELSE 0 END) AS log_28,
        SUM(CASE WHEN TYPE = 'ORDER_28'      THEN METRIC ELSE 0 END) AS order_28,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_HANDOFF' THEN METRIC END)     AS avg_dias_handoff,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_LOG'     THEN METRIC END)     AS avg_dias_log,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_ORDER'   THEN METRIC END)     AS avg_dias_order
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'HUNTING'
      AND CHANNEL_GROUP = 'HUNTING'
    GROUP BY WEEK
),
elc_target AS (
    SELECT WEEK, SUM(TARGET) AS target_total_new_available_stores_hunting
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'HUNTING'
      AND CHANNEL_GROUP = 'HUNTING'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY WEEK
),
ht_days AS (
    SELECT
        COUNTRY,
        WEEK_DATE AS WEEK,
        CASE
            WHEN AGING_CATEGORY_FINAL = 'New Entry' THEN '01 - new entry'
            WHEN AGING_CATEGORY_FINAL = 'Junior'    THEN '02 - junior'
            WHEN AGING_CATEGORY_FINAL = 'Senior'    THEN '03 - senior'
        END AS AGING,
        HUNTER_EMAIL,
        SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
    WHERE Q = :quarter AND HC = 1
    GROUP BY 1, 2, 3, 4
    HAVING AGING IS NOT NULL
),
ht_target_prod AS (
    SELECT COUNTRY, WEEK, AGING, AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD
    WHERE Q = :quarter AND TIPO_TARGET = 'PRODUCTIVIDAD'
    GROUP BY 1, 2, 3
),
ht_calc_target AS (
    SELECT
        d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_hunting_store_created,
        SUM(d.dias_trabajados_reales)                          AS dias_trabajados_reales_total
    FROM ht_days d
    JOIN ht_target_prod t ON d.COUNTRY = t.COUNTRY AND d.WEEK = t.WEEK AND d.AGING = t.AGING
    GROUP BY 1
),
ht_actual AS (
    SELECT
        WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END)                                     AS total_hunting_headcount,
        COUNT(DISTINCT CASE WHEN HC = 1 AND AGING_CATEGORY_FINAL = 'Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC = 1 THEN HUNTER_EMAIL END), 0)                      AS pct_hunters_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS), 0)                                      AS total_hunting_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.HT_FUNNEL_GOLD
    WHERE Q = :quarter
    GROUP BY 1
),
ht_hc_target AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END)                                   AS target_hunting_headcount,
        SUM(CASE WHEN TIPO_TARGET = 'HC' AND AGING = '03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET = 'HC' THEN TARGET ELSE 0 END), 0)                    AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_HT_2026_GOLD
    WHERE Q = :quarter
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ha.WEEK, hc.WEEK, tc.WEEK)              AS WEEK,
    ea.total_new_available_stores_hunting,
    et.target_total_new_available_stores_hunting,
    ea.total_hunting_store_created,
    tc.target_hunting_store_created,
    ha.total_hunting_productivity,
    tc.target_hunting_store_created / NULLIF(tc.dias_trabajados_reales_total, 0) AS target_hunting_productivity,
    ha.total_hunting_headcount,
    hc.target_hunting_headcount,
    ha.pct_hunters_old,
    hc.pct_target_hc_old,
    -- Nuevas métricas de funnel (ratios sobre CREATED)
    ea.perfect_stores / NULLIF(ea.total_hunting_store_created, 0)      AS pct_perfect_stores,
    ea.handoff_3      / NULLIF(ea.total_hunting_store_created, 0)      AS pct_handoff_3d,
    ea.handoff_7      / NULLIF(ea.total_hunting_store_created, 0)      AS pct_handoff_7d,
    ea.log_7          / NULLIF(ea.total_hunting_store_created, 0)      AS pct_login_7d,
    ea.handoff_28     / NULLIF(ea.total_hunting_store_created, 0)      AS pct_handoff_28d,
    ea.log_28         / NULLIF(ea.total_hunting_store_created, 0)      AS pct_login_28d,
    ea.order_28       / NULLIF(ea.total_hunting_store_created, 0)      AS pct_first_order,
    ea.avg_dias_handoff,
    ea.avg_dias_log,
    ea.avg_dias_order
FROM elc_actual ea
FULL OUTER JOIN elc_target    et ON ea.WEEK = et.WEEK
FULL OUTER JOIN ht_actual     ha ON COALESCE(ea.WEEK, et.WEEK) = ha.WEEK
FULL OUTER JOIN ht_hc_target  hc ON COALESCE(ea.WEEK, et.WEEK, ha.WEEK) = hc.WEEK
FULL OUTER JOIN ht_calc_target tc ON COALESCE(ea.WEEK, et.WEEK, ha.WEEK, hc.WEEK) = tc.WEEK
ORDER BY 1;

-- =========================================================
-- 5) inside_sales_outbound_query
--    Métricas existentes + nuevas métricas de funnel
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE'     THEN METRIC ELSE 0 END) AS total_new_available_stores_is_outbound,
        SUM(CASE WHEN TYPE = 'CREATED'       THEN METRIC ELSE 0 END) AS total_is_outbound_store_created,
        SUM(CASE WHEN TYPE = 'PERFECT STORE' THEN METRIC ELSE 0 END) AS perfect_stores,
        SUM(CASE WHEN TYPE = 'HANDOFF_3'     THEN METRIC ELSE 0 END) AS handoff_3,
        SUM(CASE WHEN TYPE = 'HANDOFF_7'     THEN METRIC ELSE 0 END) AS handoff_7,
        SUM(CASE WHEN TYPE = 'HANDOFF_28'    THEN METRIC ELSE 0 END) AS handoff_28,
        SUM(CASE WHEN TYPE = 'LOG_7'         THEN METRIC ELSE 0 END) AS log_7,
        SUM(CASE WHEN TYPE = 'LOG_28'        THEN METRIC ELSE 0 END) AS log_28,
        SUM(CASE WHEN TYPE = 'ORDER_28'      THEN METRIC ELSE 0 END) AS order_28,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_HANDOFF' THEN METRIC END)     AS avg_dias_handoff,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_LOG'     THEN METRIC END)     AS avg_dias_log,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_ORDER'   THEN METRIC END)     AS avg_dias_order
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES OUTBOUND'
    GROUP BY WEEK
),
elc_target AS (
    SELECT WEEK, SUM(TARGET) AS target_total_new_available_stores_is_outbound
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES' AND CHANNEL_GROUP = 'INSIDE SALES OUTBOUND'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY WEEK
),
is_days AS (
    SELECT COUNTRY, WEEK_DATE AS WEEK, PROYECTO,
        CASE WHEN AGING_CATEGORY_FINAL='New Entry' THEN '01 - new entry'
             WHEN AGING_CATEGORY_FINAL='Junior'    THEN '02 - junior'
             WHEN AGING_CATEGORY_FINAL='Senior'    THEN '03 - senior' END AS AGING,
        HUNTER_EMAIL, SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter AND HC = 1 AND PROYECTO = 'OUTBOUND'
    GROUP BY 1, 2, 3, 4, 5
    HAVING AGING IS NOT NULL
),
is_target_prod AS (
    SELECT COUNTRY, WEEK, PROYECTO, AGING, AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter AND TIPO_TARGET = 'PRODUCTIVIDAD' AND PROYECTO = 'OUTBOUND'
    GROUP BY 1, 2, 3, 4
),
is_calc_target AS (
    SELECT d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_is_outbound_store_created,
        SUM(d.dias_trabajados_reales)                          AS dias_trabajados_reales_total
    FROM is_days d
    JOIN is_target_prod t ON d.COUNTRY=t.COUNTRY AND d.WEEK=t.WEEK AND d.PROYECTO=t.PROYECTO AND d.AGING=t.AGING
    GROUP BY 1
),
is_actual AS (
    SELECT WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC=1 THEN HUNTER_EMAIL END)                                     AS total_is_outbound_headcount,
        COUNT(DISTINCT CASE WHEN HC=1 AND AGING_CATEGORY_FINAL='Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC=1 THEN HUNTER_EMAIL END), 0)                      AS pct_agents_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS), 0)                                    AS total_is_outbound_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter AND PROYECTO = 'OUTBOUND'
    GROUP BY 1
),
is_hc_target AS (
    SELECT WEEK,
        SUM(CASE WHEN TIPO_TARGET='HC' THEN TARGET ELSE 0 END)                                   AS target_is_outbound_headcount,
        SUM(CASE WHEN TIPO_TARGET='HC' AND AGING='03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET='HC' THEN TARGET ELSE 0 END), 0)                    AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter AND PROYECTO = 'OUTBOUND'
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK, ic.WEEK)            AS WEEK,
    ea.total_new_available_stores_is_outbound,
    et.target_total_new_available_stores_is_outbound,
    ea.total_is_outbound_store_created,
    ic.target_is_outbound_store_created,
    ia.total_is_outbound_productivity,
    ic.target_is_outbound_store_created / NULLIF(ic.dias_trabajados_reales_total, 0) AS target_is_outbound_productivity,
    ia.total_is_outbound_headcount,
    ih.target_is_outbound_headcount,
    ia.pct_agents_old,
    ih.pct_target_hc_old,
    ea.perfect_stores / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_perfect_stores,
    ea.handoff_3      / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_handoff_3d,
    ea.handoff_7      / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_handoff_7d,
    ea.log_7          / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_login_7d,
    ea.handoff_28     / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_handoff_28d,
    ea.log_28         / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_login_28d,
    ea.order_28       / NULLIF(ea.total_is_outbound_store_created, 0) AS pct_first_order,
    ea.avg_dias_handoff,
    ea.avg_dias_log,
    ea.avg_dias_order
FROM elc_actual ea
FULL OUTER JOIN elc_target    et ON ea.WEEK = et.WEEK
FULL OUTER JOIN is_actual     ia ON COALESCE(ea.WEEK, et.WEEK) = ia.WEEK
FULL OUTER JOIN is_hc_target  ih ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK) = ih.WEEK
FULL OUTER JOIN is_calc_target ic ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK) = ic.WEEK
ORDER BY 1;

-- =========================================================
-- 6) inside_sales_inbound_query
--    Métricas existentes + nuevas métricas de funnel
-- =========================================================
WITH elc_actual AS (
    SELECT
        WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE'     THEN METRIC ELSE 0 END) AS total_new_available_stores_is_inbound,
        SUM(CASE WHEN TYPE = 'CREATED'       THEN METRIC ELSE 0 END) AS total_is_inbound_store_created,
        SUM(CASE WHEN TYPE = 'PERFECT STORE' THEN METRIC ELSE 0 END) AS perfect_stores,
        SUM(CASE WHEN TYPE = 'HANDOFF_3'     THEN METRIC ELSE 0 END) AS handoff_3,
        SUM(CASE WHEN TYPE = 'HANDOFF_7'     THEN METRIC ELSE 0 END) AS handoff_7,
        SUM(CASE WHEN TYPE = 'HANDOFF_28'    THEN METRIC ELSE 0 END) AS handoff_28,
        SUM(CASE WHEN TYPE = 'LOG_7'         THEN METRIC ELSE 0 END) AS log_7,
        SUM(CASE WHEN TYPE = 'LOG_28'        THEN METRIC ELSE 0 END) AS log_28,
        SUM(CASE WHEN TYPE = 'ORDER_28'      THEN METRIC ELSE 0 END) AS order_28,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_HANDOFF' THEN METRIC END)     AS avg_dias_handoff,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_LOG'     THEN METRIC END)     AS avg_dias_log,
        AVG(CASE WHEN TYPE = 'AVG_DIAS_ORDER'   THEN METRIC END)     AS avg_dias_order
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES'
      AND CHANNEL_GROUP = 'INSIDE SALES INBOUND'
    GROUP BY WEEK
),
elc_target AS (
    SELECT WEEK, SUM(TARGET) AS target_total_new_available_stores_is_inbound
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter
      AND TEAM = 'INSIDE SALES' AND CHANNEL_GROUP = 'INSIDE SALES INBOUND'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY WEEK
),
is_days AS (
    SELECT COUNTRY, WEEK_DATE AS WEEK, PROYECTO,
        CASE WHEN AGING_CATEGORY_FINAL='New Entry' THEN '01 - new entry'
             WHEN AGING_CATEGORY_FINAL='Junior'    THEN '02 - junior'
             WHEN AGING_CATEGORY_FINAL='Senior'    THEN '03 - senior' END AS AGING,
        HUNTER_EMAIL, SUM(DIAS_TRABAJADOS) AS dias_trabajados_reales
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter AND HC = 1 AND PROYECTO = 'INBOUND'
    GROUP BY 1, 2, 3, 4, 5
    HAVING AGING IS NOT NULL
),
is_target_prod AS (
    SELECT COUNTRY, WEEK, PROYECTO, AGING, AVG(TARGET) AS productividad_target
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter AND TIPO_TARGET = 'PRODUCTIVIDAD' AND PROYECTO = 'INBOUND'
    GROUP BY 1, 2, 3, 4
),
is_calc_target AS (
    SELECT d.WEEK,
        SUM(t.productividad_target * d.dias_trabajados_reales) AS target_is_inbound_store_created,
        SUM(d.dias_trabajados_reales)                          AS dias_trabajados_reales_total
    FROM is_days d
    JOIN is_target_prod t ON d.COUNTRY=t.COUNTRY AND d.WEEK=t.WEEK AND d.PROYECTO=t.PROYECTO AND d.AGING=t.AGING
    GROUP BY 1
),
is_actual AS (
    SELECT WEEK_DATE AS WEEK,
        COUNT(DISTINCT CASE WHEN HC=1 THEN HUNTER_EMAIL END)                                     AS total_is_inbound_headcount,
        COUNT(DISTINCT CASE WHEN HC=1 AND AGING_CATEGORY_FINAL='Senior' THEN HUNTER_EMAIL END)
          / NULLIF(COUNT(DISTINCT CASE WHEN HC=1 THEN HUNTER_EMAIL END), 0)                      AS pct_agents_old,
        SUM(STORES_TOTALES) / NULLIF(SUM(DIAS_TRABAJADOS), 0)                                    AS total_is_inbound_productivity
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.IS_FUNNEL_GOLD
    WHERE Q = :quarter AND PROYECTO = 'INBOUND'
    GROUP BY 1
),
is_hc_target AS (
    SELECT WEEK,
        SUM(CASE WHEN TIPO_TARGET='HC' THEN TARGET ELSE 0 END)                                   AS target_is_inbound_headcount,
        SUM(CASE WHEN TIPO_TARGET='HC' AND AGING='03 - senior' THEN TARGET ELSE 0 END)
          / NULLIF(SUM(CASE WHEN TIPO_TARGET='HC' THEN TARGET ELSE 0 END), 0)                    AS pct_target_hc_old
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_IS_2026_GOLD
    WHERE Q = :quarter AND PROYECTO = 'INBOUND'
    GROUP BY 1
)
SELECT
    COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK, ic.WEEK)            AS WEEK,
    ea.total_new_available_stores_is_inbound,
    et.target_total_new_available_stores_is_inbound,
    ea.total_is_inbound_store_created,
    ic.target_is_inbound_store_created,
    ia.total_is_inbound_productivity,
    ic.target_is_inbound_store_created / NULLIF(ic.dias_trabajados_reales_total, 0) AS target_is_inbound_productivity,
    ia.total_is_inbound_headcount,
    ih.target_is_inbound_headcount,
    ia.pct_agents_old,
    ih.pct_target_hc_old,
    ea.perfect_stores / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_perfect_stores,
    ea.handoff_3      / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_handoff_3d,
    ea.handoff_7      / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_handoff_7d,
    ea.log_7          / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_login_7d,
    ea.handoff_28     / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_handoff_28d,
    ea.log_28         / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_login_28d,
    ea.order_28       / NULLIF(ea.total_is_inbound_store_created, 0)  AS pct_first_order,
    ea.avg_dias_handoff,
    ea.avg_dias_log,
    ea.avg_dias_order
FROM elc_actual ea
FULL OUTER JOIN elc_target    et ON ea.WEEK = et.WEEK
FULL OUTER JOIN is_actual     ia ON COALESCE(ea.WEEK, et.WEEK) = ia.WEEK
FULL OUTER JOIN is_hc_target  ih ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK) = ih.WEEK
FULL OUTER JOIN is_calc_target ic ON COALESCE(ea.WEEK, et.WEEK, ia.WEEK, ih.WEEK) = ic.WEEK
ORDER BY 1;

-- =========================================================
-- 7) self_onboarding_query
-- =========================================================
WITH so_actual AS (
    SELECT WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN METRIC ELSE 0 END) AS total_new_available_stores_self_onboarding
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter AND TEAM = 'SELF-ONBOARDING' AND CHANNEL_GROUP = 'SELF-ONBOARDING'
      AND TYPE = 'AVAILABLE'
    GROUP BY WEEK
),
so_target AS (
    SELECT WEEK, SUM(TARGET) AS target_total_new_available_stores_self_onboarding
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter AND TEAM = 'SELF-ONBOARDING' AND CHANNEL_GROUP = 'SELF-ONBOARDING'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY WEEK
)
SELECT
    COALESCE(a.WEEK, t.WEEK)                                AS WEEK,
    a.total_new_available_stores_self_onboarding,
    t.target_total_new_available_stores_self_onboarding
FROM so_actual a
FULL OUTER JOIN so_target t ON a.WEEK = t.WEEK
ORDER BY 1;

-- =========================================================
-- 8) brand_expansion_query
-- =========================================================
WITH be_actual AS (
    SELECT WEEK,
        SUM(CASE WHEN TYPE = 'AVAILABLE' THEN METRIC ELSE 0 END) AS total_new_available_stores_brand_expansion,
        SUM(CASE WHEN TYPE = 'CREATED'   THEN METRIC ELSE 0 END) AS total_brand_expansion_store_created
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.ELC_FUNNEL_GOLD
    WHERE Q = :quarter AND TEAM = 'BRAND EXPANSION' AND CHANNEL_GROUP = 'BRAND EXPANSION'
      AND TYPE IN ('AVAILABLE', 'CREATED')
    GROUP BY WEEK
),
be_target AS (
    SELECT WEEK, SUM(TARGET) AS target_total_new_available_stores_brand_expansion
    FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD
    WHERE Q = :quarter AND TEAM = 'BRAND EXPANSION' AND CHANNEL_GROUP = 'BRAND EXPANSION'
      AND TIPO_TARGET = 'AVAILABLE'
    GROUP BY WEEK
)
SELECT
    COALESCE(a.WEEK, t.WEEK)                                AS WEEK,
    a.total_new_available_stores_brand_expansion,
    t.target_total_new_available_stores_brand_expansion,
    a.total_brand_expansion_store_created
FROM be_actual a
FULL OUTER JOIN be_target t ON a.WEEK = t.WEEK
ORDER BY 1;


-- =========================================================
-- 9) early_churn_query
--    Churn real vs target por canal y age (M1, M2, M3)
--    Fuentes: EARLY_CHURN_SILVER + TG_EARLY_CHURN_CHANNEL
--
--    REGLAS CRÍTICAS:
--      - Excluir siempre Brasil: COUNTRY != 'BR'
--      - Targets siempre con COUNTRY = 'TOTAL'
--      - Churn % = SUM(CHURN) / SUM(TOTAL_STORE)  — NUNCA COUNT ni SUM directa
--      - TOTAL = agregado de todos los canales mapeados (sin filtrar por canal)
--      - Semanas: solo las cerradas del quarter (:quarter), igual que el eje NF Q2
--      - Una semana cerrada es: WEEK < DATE_TRUNC('week', CONVERT_TIMEZONE('America/Bogota', CURRENT_TIMESTAMP))
--
--    QTD (calcular fuera de la query, en el agente):
--      - Churn QTD = SUM(CHURN_S todas las semanas) / SUM(TOTAL_S todas las semanas)
--      - Target QTD = SUM(target_raw * TOTAL_S) / SUM(TOTAL_S)   donde target_raw = TARGET_%CHURN_Mx
--      - GAP QTD = churn_qtd - target_qtd
--      - INVERTIR colores: GAP positivo = rojo (malo), GAP negativo = verde (bueno)
--
--    ANOMALÍAS: si |delta_pp| > 40 en cualquier celda, marcar y alertar
-- =========================================================

WITH silver AS (
  SELECT
    WEEK,
    AGE,
    CASE
      WHEN UPPER(CHANNEL_AM) = 'HUNTING'         THEN 'HUNTING'
      WHEN UPPER(CHANNEL_AM) = 'INSIDE SALES'    THEN 'IS'
      WHEN UPPER(CHANNEL_AM) = 'BRAND EXPANSION' THEN 'BE'
      WHEN UPPER(CHANNEL_AM) = 'SELF-ONBOARDING' THEN 'SOB'
      ELSE NULL
    END AS CANAL,
    CHURN,
    TOTAL_STORE
  FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.EARLY_CHURN_SILVER
  WHERE COUNTRY != 'BR'
    AND WEEK >= (SELECT MIN(WEEK) FROM RP_GOLD_DB_PROD.RESTAURANTS_HUNTING.TG_ELC_2026_GOLD WHERE Q = :quarter)
    AND WEEK < DATE_TRUNC('week', CONVERT_TIMEZONE('America/Bogota', CURRENT_TIMESTAMP))
),
agg_canal AS (
  SELECT WEEK, AGE, CANAL,
    SUM(CHURN)       AS CHURN_S,
    SUM(TOTAL_STORE) AS TOTAL_S,
    ROUND(SUM(CHURN) / NULLIF(SUM(TOTAL_STORE), 0) * 100, 1) AS CHURN_PCT
  FROM silver
  WHERE CANAL IS NOT NULL
  GROUP BY WEEK, AGE, CANAL
),
agg_total AS (
  SELECT WEEK, AGE,
    'TOTAL'          AS CANAL,
    SUM(CHURN)       AS CHURN_S,
    SUM(TOTAL_STORE) AS TOTAL_S,
    ROUND(SUM(CHURN) / NULLIF(SUM(TOTAL_STORE), 0) * 100, 1) AS CHURN_PCT
  FROM silver
  GROUP BY WEEK, AGE
),
all_data AS (
  SELECT * FROM agg_canal
  UNION ALL
  SELECT * FROM agg_total
),
tg AS (
  SELECT
    WEEK::DATE       AS WEEK,
    CHANNEL_AM       AS CANAL,
    "TARGET_%CHURN_M1" AS TG_M1,
    "TARGET_%CHURN_M2" AS TG_M2,
    "TARGET_%CHURN_M3" AS TG_M3
  FROM FIVETRAN.RESTAURANTS_HUNTING.TG_EARLY_CHURN_CHANNEL
  WHERE COUNTRY = 'TOTAL'
)
SELECT
  a.WEEK,
  a.AGE,
  a.CANAL,
  a.CHURN_S                                                              AS churn_stores,
  a.TOTAL_S                                                              AS total_stores,
  a.CHURN_PCT / 100                                                      AS churn_pct,       -- escala 0-1
  CASE a.AGE
    WHEN 'M1' THEN t.TG_M1
    WHEN 'M2' THEN t.TG_M2
    WHEN 'M3' THEN t.TG_M3
  END                                                                    AS target_pct,      -- escala 0-1
  CASE a.AGE
    WHEN 'M1' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M1) * 100, 1)
    WHEN 'M2' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M2) * 100, 1)
    WHEN 'M3' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M3) * 100, 1)
  END                                                                    AS delta_pp,
  ABS(CASE a.AGE
    WHEN 'M1' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M1) * 100, 1)
    WHEN 'M2' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M2) * 100, 1)
    WHEN 'M3' THEN ROUND((a.CHURN_PCT / 100 - t.TG_M3) * 100, 1)
  END) > 40                                                              AS is_anomaly
FROM all_data a
LEFT JOIN tg t ON a.WEEK = t.WEEK AND a.CANAL = t.CANAL
ORDER BY
  a.AGE,
  CASE a.CANAL
    WHEN 'HUNTING' THEN 1 WHEN 'IS' THEN 2 WHEN 'SOB' THEN 3 WHEN 'BE' THEN 4 WHEN 'TOTAL' THEN 5
  END,
  a.WEEK;

-- NOTA DE VALIDACIÓN post-ejecución:
-- Verificar que existen filas para los 5 canales (HUNTING, IS, SOB, BE, TOTAL) en cada AGE x WEEK.
-- Si is_anomaly = TRUE en alguna celda, agregar nota de alerta encima de la tabla de ese age.
-- churn_pct y target_pct están en escala 0-1 (ej: 0.097 = 9.7%).
