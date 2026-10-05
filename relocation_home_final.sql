DECLARE post_start DATE DEFAULT DATE '2025-12-01';
DECLARE post_end   DATE DEFAULT DATE '2026-03-31';

CREATE OR REPLACE TABLE
  `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_displacement_home_amda_final` AS

WITH
home_affected AS (
  SELECT msisdn, home_prov, home_kab, home_kec, home_desa
  FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_amda_home_baseline_fix`
  WHERE msisdn IS NOT NULL
    AND home_kab IN ('1102', '1103', '1104', '1105', '1106', '1107', '1108', '1109', '1110',
                     '1111', '1113', '1114', '1115', '1117', '1118', '1173', '1174', '1175')
),

stay AS (
  SELECT DISTINCT
    m.msisdn, m.latitude, m.longitude,
    m.activity_prov, m.activity_kab, m.activity_kec, m.iddesa AS activity_desa,
    m.event_date, m.end_datetime,
    FORMAT_DATE('%Y-%m', m.event_date) AS event_month,
    `appl-ext-das-dm102-prd-b97y.wisnus_2026.ST_H3`(ST_GEOGPOINT(m.longitude, m.latitude), 8) AS h3_8,
    EXTRACT(HOUR FROM m.end_datetime) AS event_hour
  FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.master_mobility_bencana` AS m
  WHERE m.event_date BETWEEN post_start AND post_end
    AND EXTRACT(DAYOFWEEK FROM m.event_date) NOT IN (1, 7)
    AND m.latitude IS NOT NULL
    AND m.longitude IS NOT NULL
    AND m.msisdn IN (SELECT msisdn FROM home_affected)
),

daily_site AS (
  SELECT
    msisdn, event_month, event_date, h3_8, activity_desa,
    ANY_VALUE(activity_prov) AS activity_prov,
    ANY_VALUE(activity_kab)  AS activity_kab,
    ANY_VALUE(activity_kec)  AS activity_kec,
    COUNT(*) AS N,
    IF(MIN(event_hour) >= 12, 23 - MIN(event_hour), MIN(event_hour)) AS hour_rev
  FROM stay
  GROUP BY msisdn, event_month, event_date, h3_8, activity_desa
),

anchor AS (
  SELECT
    msisdn, event_month, h3_8, activity_desa,
    ANY_VALUE(activity_prov) AS activity_prov,
    ANY_VALUE(activity_kab)  AS activity_kab,
    ANY_VALUE(activity_kec)  AS activity_kec,
    SUM(N)                          AS N,
    COUNT(DISTINCT event_date)      AS N_date,
    ROUND(AVG(hour_rev), 2)         AS AVG_hour,
    ROUND(STDDEV_SAMP(hour_rev), 2) AS SD_hour
  FROM daily_site
  GROUP BY msisdn, event_month, h3_8, activity_desa
),

post_anchor AS (
  SELECT *
  FROM anchor
  WHERE N_date >= 5
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY msisdn, event_month
    ORDER BY N_date DESC, N DESC, AVG_hour ASC, SD_hour ASC, h3_8, activity_desa
  ) = 1
),

months AS (
  SELECT FORMAT_DATE('%Y-%m', d) AS event_month
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE_TRUNC(post_start, MONTH), post_end, INTERVAL 1 MONTH)) AS d
)


SELECT
  t.event_month,
  h.home_prov,
  h.home_kab,
  h.home_kec,
  h.home_desa,
  p.activity_prov AS post_prov,
  p.activity_kab  AS post_kab,
  p.activity_kec  AS post_kec,
  p.activity_desa AS post_desa,
  CASE
    WHEN p.activity_desa IS NULL         THEN 'Missing'
    WHEN h.home_desa = p.activity_desa   THEN 'Stable'
    ELSE 'Relocated'
  END AS displacement_status,
  CASE
    WHEN p.activity_desa IS NULL         THEN 'Missing'
    WHEN h.home_prov <> p.activity_prov  THEN 'Inter-Provinsi'
    WHEN h.home_kab  <> p.activity_kab   THEN 'Inter-Kabupaten'
    WHEN h.home_kec  <> p.activity_kec   THEN 'Inter-Kecamatan'
    WHEN h.home_desa <> p.activity_desa  THEN 'Inter-Desa'
    ELSE 'No Change'
  END AS movement_type,
  COUNT(DISTINCT h.msisdn) AS n_subscriber
FROM home_affected AS h
CROSS JOIN months AS t
LEFT JOIN post_anchor AS p
  ON  p.msisdn = h.msisdn
  AND p.event_month = t.event_month
  AND p.AVG_hour < 7.0 
GROUP BY ALL;