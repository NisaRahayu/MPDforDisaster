DECLARE start_date DATE DEFAULT DATE '2025-11-25';
DECLARE end_date   DATE DEFAULT DATE '2025-12-31';

CREATE OR REPLACE TABLE
  `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_displacement_harian_final` AS

WITH
baseline AS (
  SELECT DISTINCT
    CAST(msisdn           AS STRING) AS msisdn,
    CAST(home_desa        AS STRING) AS home_desa,
    CAST(work_desa        AS STRING) AS work_desa,
    CAST(mobility_profile AS STRING) AS mobility_profile
  FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.bencana_kajian_amda_home_baseline_fix`
  WHERE msisdn IS NOT NULL
    AND home_desa IS NOT NULL
),

stopspot AS (
  SELECT
    CAST(s.msisdn AS STRING) AS msisdn,
    s.event_date,
    CAST(s.idprov AS STRING) AS idprov,
    CAST(s.idkab  AS STRING) AS idkab,
    CAST(s.idkec  AS STRING) AS idkec,
    CAST(d.iddesa AS STRING) AS dest_desa,
    COALESCE(SAFE_CAST(s.time_interval AS FLOAT64), 0) AS time_interval
  FROM `appl-ext-das-dm102-prd-b97y.wisnus_2026.5perc_wisnus_0_stopspot` AS s
  JOIN `appl-ext-das-dm102-prd-b97y.wisnus_2026.assets_2024_idn38_desa` AS d
    ON  CAST(d.idkab AS STRING) = CAST(s.idkab AS STRING)
    AND CAST(d.idkec AS STRING) = CAST(s.idkec AS STRING)
    AND ST_COVERS(
          d.geometry,
          ST_GEOGPOINT(SAFE_CAST(s.longitude AS FLOAT64), SAFE_CAST(s.latitude AS FLOAT64))
        )
  WHERE s.event_date BETWEEN start_date AND end_date
    AND d.iddesa IS NOT NULL
    AND CAST(s.msisdn AS STRING) IN (SELECT msisdn FROM baseline)
),

daily_mode AS (
  SELECT msisdn, event_date, dest_desa
  FROM stopspot
  GROUP BY msisdn, event_date, idprov, idkab, idkec, dest_desa
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY msisdn, event_date
    ORDER BY SUM(time_interval) DESC, COUNT(*) DESC, dest_desa
  ) = 1
),

daily AS (
  SELECT
    tanggal,
    b.msisdn,
    b.home_desa,
    m.dest_desa,
    CAST(m.dest_desa != b.home_desa AS INT64) AS displaced_naive,
    CASE
      WHEN m.dest_desa IS NULL       THEN NULL
      WHEN m.dest_desa = b.home_desa THEN 0
      WHEN b.mobility_profile IN ('local_resident', 'home_only') THEN 1
      WHEN b.mobility_profile IN ('inter_desa_commuter',
                                  'inter_kecamatan_commuter',
                                  'inter_kabupaten_commuter')
       AND (EXTRACT(DAYOFWEEK FROM tanggal) IN (1, 7) 
            OR m.dest_desa != b.work_desa)             
                                     THEN 1
      ELSE 0
    END AS displaced_ca
  FROM baseline AS b
  CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(start_date, end_date)) AS tanggal
  LEFT JOIN daily_mode AS m
    ON  m.msisdn = b.msisdn
    AND m.event_date = tanggal
)

SELECT
  tanggal,
  home_desa,
  dest_desa,
  COUNT(DISTINCT IF(displaced_ca = 1,    msisdn, NULL)) AS displaced_ca,
  COUNT(DISTINCT IF(displaced_naive = 1, msisdn, NULL)) AS displaced_naive,
  COUNT(DISTINCT IF(displaced_ca = 0,    msisdn, NULL)) AS stable,
  COUNT(DISTINCT IF(dest_desa IS NULL,   msisdn, NULL)) AS missing
FROM daily
GROUP BY tanggal, home_desa, dest_desa;