CREATE OR REPLACE TABLE `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_impact_final` AS

WITH

master_bencana AS (
    SELECT
        msisdn,
        disaster_name,
        DATE(calling_date) AS event_date,
        CAST(iddesa AS STRING) AS id_desa,
        SUBSTR(CAST(iddesa AS STRING), 1, 4) AS id_kab,
        SUBSTR(CAST(iddesa AS STRING), 1, 6) AS id_kec
    FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.master_raw_bencana`
    WHERE msisdn IS NOT NULL
        AND calling_date IS NOT NULL
        AND iddesa IS NOT NULL
        AND SUBSTR(CAST(iddesa AS STRING), 1, 4) IN (
            '1102', '1103', '1104', '1105', '1106', '1107', '1108', '1109',
            '1110', '1111', '1113', '1114', '1115', '1117', '1118', '1173', '1174', '1175'
        )
),

daily_desa AS (
    SELECT id_desa, event_date, COUNT(DISTINCT msisdn) AS n_subscriber
    FROM master_bencana
    GROUP BY id_desa, event_date
),

daily_desa_base AS (
    SELECT id_desa, event_date, n_subscriber
    FROM daily_desa
    WHERE event_date BETWEEN DATE '2025-10-01' AND DATE '2025-11-24'
),

stats_desa AS (
    SELECT id_desa, AVG(n_subscriber) AS mu_baseline, STDDEV_SAMP(n_subscriber) AS sigma_baseline
    FROM daily_desa_base
    GROUP BY id_desa
    HAVING AVG(n_subscriber) >= 1 AND STDDEV_SAMP(n_subscriber) > 0
),

impact_dates AS (
    SELECT date_val AS event_date
    FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2025-11-25', DATE '2026-01-31')) AS date_val
),

desa_skeleton AS (
    SELECT s.id_desa, d.event_date
    FROM stats_desa AS s
    CROSS JOIN impact_dates AS d
),

daily_desa_impact AS (
    SELECT id_desa, event_date, n_subscriber
    FROM daily_desa
    WHERE event_date BETWEEN DATE '2025-11-25' AND DATE '2026-01-31'
),

zscore_desa AS (
    SELECT
        s.id_desa,
        s.event_date,
        COALESCE(i.n_subscriber, 0) AS n_subscriber,
        b.mu_baseline,
        b.sigma_baseline,
        SAFE_DIVIDE(COALESCE(i.n_subscriber, 0) - b.mu_baseline, b.sigma_baseline) AS z_score
    FROM desa_skeleton AS s
    INNER JOIN stats_desa AS b ON s.id_desa = b.id_desa
    LEFT JOIN daily_desa_impact AS i ON s.id_desa = i.id_desa AND s.event_date = i.event_date
),

daily_kec AS (
    SELECT id_kec, event_date, COUNT(DISTINCT msisdn) AS n_subscriber
    FROM master_bencana
    GROUP BY id_kec, event_date
),

daily_kec_base AS (
    SELECT id_kec, event_date, n_subscriber
    FROM daily_kec
    WHERE event_date BETWEEN DATE '2025-10-01' AND DATE '2025-11-24'
),

stats_kec AS (
    SELECT id_kec, AVG(n_subscriber) AS mu_baseline, STDDEV_SAMP(n_subscriber) AS sigma_baseline
    FROM daily_kec_base
    GROUP BY id_kec
    HAVING AVG(n_subscriber) >= 1 AND STDDEV_SAMP(n_subscriber) > 0
),

kec_skeleton AS (
    SELECT s.id_kec, d.event_date
    FROM stats_kec AS s
    CROSS JOIN impact_dates AS d
),

daily_kec_impact AS (
    SELECT id_kec, event_date, n_subscriber
    FROM daily_kec
    WHERE event_date BETWEEN DATE '2025-11-25' AND DATE '2026-01-31'
),

zscore_kec AS (
    SELECT
        s.id_kec,
        s.event_date,
        COALESCE(i.n_subscriber, 0) AS n_subscriber,
        b.mu_baseline,
        b.sigma_baseline,
        SAFE_DIVIDE(COALESCE(i.n_subscriber, 0) - b.mu_baseline, b.sigma_baseline) AS z_score
    FROM kec_skeleton AS s
    INNER JOIN stats_kec AS b ON s.id_kec = b.id_kec
    LEFT JOIN daily_kec_impact AS i ON s.id_kec = i.id_kec AND s.event_date = i.event_date
)

SELECT 'DESA' AS level, CAST(id_desa AS STRING) AS wilayah, event_date, n_subscriber, mu_baseline, sigma_baseline, z_score
FROM zscore_desa

UNION ALL

SELECT 'KEC' AS level, CAST(id_kec AS STRING) AS wilayah, event_date, n_subscriber, mu_baseline, sigma_baseline, z_score
FROM zscore_kec

ORDER BY level, wilayah, event_date;