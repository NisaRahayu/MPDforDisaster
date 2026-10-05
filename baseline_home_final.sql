CREATE OR REPLACE TABLE `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_amda_home_baseline_fix` AS
WITH
master_bencana AS (
  SELECT msisdn, latitude, longitude, home_kab, activity_prov, activity_kab, activity_kec, iddesa AS activity_desa,
    event_date, start_datetime, end_datetime, disaster_name, start_date, d_date, end_date,
    `appl-ext-das-dm102-prd-b97y.wisnus_2026.ST_H3`(ST_GEOGPOINT(longitude, latitude), 8) AS h3_8,
    EXTRACT(HOUR FROM end_datetime) AS event_hour
  FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.master_mobility_bencana`
  WHERE event_date BETWEEN DATE '2025-10-01' AND DATE '2025-11-24'
    AND msisdn IS NOT NULL AND latitude IS NOT NULL AND longitude IS NOT NULL AND event_date IS NOT NULL
),
anchor_0 AS (
  SELECT DISTINCT *, CASE WHEN EXTRACT(DAYOFWEEK FROM event_date) IN (1, 7) THEN 'weekend' ELSE 'weekday' END AS day_type
  FROM master_bencana
),
anchor_0_weekday AS (SELECT * FROM anchor_0 WHERE day_type = 'weekday'),
anchor_1_window AS (
  SELECT *,
    COUNT(*) OVER (PARTITION BY msisdn, event_date, h3_8, activity_desa) AS N,
    ROW_NUMBER() OVER (PARTITION BY msisdn, event_date, h3_8, activity_desa ORDER BY event_hour) AS rn
  FROM anchor_0_weekday
),
anchor_1_filtered AS (
  SELECT *, CASE WHEN event_hour >= 12 THEN 23 - event_hour ELSE event_hour END AS event_hour_reverse
  FROM anchor_1_window WHERE rn = 1
),
anchor_1 AS (
  SELECT msisdn, h3_8, activity_desa,
    ANY_VALUE(activity_prov) AS activity_prov, ANY_VALUE(activity_kab) AS activity_kab, ANY_VALUE(activity_kec) AS activity_kec,
    SUM(N) AS N, COUNT(DISTINCT event_date) AS N_date,
    ROUND(AVG(event_hour_reverse), 2) AS AVG_hour, ROUND(STDDEV_SAMP(event_hour_reverse), 2) AS SD_hour
  FROM anchor_1_filtered
  GROUP BY msisdn, h3_8, activity_desa
),
home_0 AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY msisdn ORDER BY N_date DESC, N DESC, AVG_hour DESC, SD_hour ASC, h3_8 ASC, activity_desa ASC) AS rn
  FROM anchor_1 WHERE N_date >= 5 AND AVG_hour < 7.0
),
home_1 AS (
  SELECT msisdn, activity_prov AS home_prov, activity_kab AS home_kab, activity_kec AS home_kec, activity_desa AS home_desa,
    h3_8 AS home_h3_8, N AS home_N, N_date AS home_N_date, AVG_hour AS home_AVG_hour, SD_hour AS home_SD_hour
  FROM home_0 WHERE rn = 1
),
home_affected AS (
  SELECT * FROM home_1
  WHERE home_kab IN ('1102', '1103', '1104', '1105', '1106', '1107', '1108', '1109', '1110',
                     '1111', '1113', '1114', '1115', '1117', '1118', '1173', '1174', '1175')
),
work_0 AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY msisdn ORDER BY N_date DESC, N DESC, AVG_hour DESC, SD_hour ASC, h3_8 ASC, activity_desa ASC) AS rn
  FROM anchor_1 WHERE N_date >= 5 AND AVG_hour >= 7.0
),
work_1 AS (
  SELECT msisdn, activity_prov AS work_prov, activity_kab AS work_kab, activity_kec AS work_kec, activity_desa AS work_desa,
    h3_8 AS work_h3_8, N AS work_N, N_date AS work_N_date, AVG_hour AS work_AVG_hour, SD_hour AS work_SD_hour
  FROM work_0 WHERE rn = 1
),
home_work AS (
  SELECT h.msisdn,
    h.home_prov, h.home_kab, h.home_kec, h.home_desa, h.home_h3_8, h.home_N, h.home_N_date, h.home_AVG_hour, h.home_SD_hour,
    w.work_prov, w.work_kab, w.work_kec, w.work_desa, w.work_h3_8, w.work_N, w.work_N_date, w.work_AVG_hour, w.work_SD_hour
  FROM home_affected AS h
  LEFT JOIN work_1 AS w ON h.msisdn = w.msisdn
),
mobility_profile AS (
  SELECT *,
    CASE
      WHEN work_kab IS NULL THEN 'home_only'
      WHEN home_kab != work_kab THEN 'inter_kabupaten_commuter'
      WHEN home_kec != work_kec THEN 'inter_kecamatan_commuter'
      WHEN home_desa != work_desa THEN 'inter_desa_commuter'
      ELSE 'local_resident'
    END AS mobility_profile,
    '2025-10-01_2025-11-24' AS baseline_period
  FROM home_work
)
SELECT * FROM mobility_profile;