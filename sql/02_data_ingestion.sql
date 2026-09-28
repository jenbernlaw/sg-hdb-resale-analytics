-- =============================================================================
-- 02 — DATA INGESTION
-- Script:      02_data_ingestion.sql
-- Description: Loads raw source data into the database and organizes it into
--              staging tables for downstream processing.
-- Target DB:   PostgreSQL 16
-- Author:      J.B. Lawrence
-- =============================================================================

-- Ensure search path includes staging, raw, and public schemas
SET search_path TO staging, raw, public;


-- =============================================================================
-- STEP 1: BULK LOAD CSV DATASETS INTO RAW SCHEMA
-- Note: Replace file paths with the exact local path to your CSV downloads.
--       When running in psql CLI, \copy streams client files safely on macOS.
-- =============================================================================

-- Safe re-run capability (Idempotency): Truncate raw landing tables
TRUNCATE TABLE raw.hdb_resale_2015_2016;
TRUNCATE TABLE raw.hdb_resale_2017_present;

-- Bulk Load 2015-2016 Dataset
\copy raw.hdb_resale_2015_2016 FROM '/path/to/ResaleFlatPricesBasedonRegistrationDateFromJan2015toDec2016.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Bulk Load 2017-Present Dataset
\copy raw.hdb_resale_2017_present FROM '/path/to/ResaleflatpricesbasedonregistrationdatefromJan2017onwards.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');


-- =============================================================================
-- STEP 2: CONSOLIDATE DATASETS INTO STAGING TABLE
-- =============================================================================

-- Truncate staging table and reset auto-increment ID
TRUNCATE TABLE staging.hdb_resale_prices RESTART IDENTITY;

-- Consolidate both raw datasets into staging using UNION ALL
INSERT INTO staging.hdb_resale_prices (
    transaction_month,
    town,
    flat_type,
    block,
    street_name,
    storey_range,
    floor_area_sqm,
    flat_model,
    lease_commence_date,
    remaining_lease,
    resale_price,
    source_dataset
)
SELECT 
    -- Convert YYYY-MM string to standard DATE defaulting to the 1st of the month
    TO_DATE(month || '-01', 'YYYY-MM-DD') AS transaction_month,
    UPPER(TRIM(town))                     AS town,
    UPPER(TRIM(flat_type))                AS flat_type,
    TRIM(block)                           AS block,
    UPPER(TRIM(street_name))              AS street_name,
    TRIM(storey_range)                    AS storey_range,
    floor_area_sqm,
    UPPER(TRIM(flat_model))               AS flat_model,
    lease_commence_date,
    TRIM(remaining_lease)                 AS remaining_lease,
    resale_price,
    '2015_2016'                           AS source_dataset
FROM raw.hdb_resale_2015_2016

UNION ALL

SELECT 
    TO_DATE(month || '-01', 'YYYY-MM-DD') AS transaction_month,
    UPPER(TRIM(town))                     AS town,
    UPPER(TRIM(flat_type))                AS flat_type,
    TRIM(block)                           AS block,
    UPPER(TRIM(street_name))              AS street_name,
    TRIM(storey_range)                    AS storey_range,
    floor_area_sqm,
    UPPER(TRIM(flat_model))               AS flat_model,
    lease_commence_date,
    TRIM(remaining_lease)                 AS remaining_lease,
    resale_price,
    '2017_present'                        AS source_dataset
FROM raw.hdb_resale_2017_present;


-- =============================================================================
-- STEP 3: INGESTION QUALITY CHECKS & AUDIT VERIFICATION
-- =============================================================================

-- Check 1: Row Count Reconciliation across Raw and Staging layers
SELECT dataset, total_rows
FROM (
    SELECT 'raw.hdb_resale_2015_2016' AS dataset, COUNT(*) AS total_rows, 1 AS sort_order  FROM raw.hdb_resale_2015_2016
    UNION ALL
    SELECT 'raw.hdb_resale_2017_present', COUNT(*), 2 FROM raw.hdb_resale_2017_present
    UNION ALL
    SELECT 'staging.hdb_resale_prices', COUNT(*), 3 FROM staging.hdb_resale_prices
) AS row_audit
ORDER BY sort_order;

-- Check 2: Confirm Staging row count equals combined Raw source row counts
SELECT 
    (SELECT COUNT(*) FROM staging.hdb_resale_prices) = 
    (SELECT COUNT(*) FROM raw.hdb_resale_2015_2016) + (SELECT COUNT(*) FROM raw.hdb_resale_2017_present) 
    AS is_row_count_reconciled;

-- Check 3: Verify minimum and maximum transaction dates per source dataset
SELECT 
    source_dataset,
    COUNT(*) AS record_count,
    MIN(transaction_month) AS min_transaction_date,
    MAX(transaction_month) AS max_transaction_date
FROM staging.hdb_resale_prices
GROUP BY source_dataset
ORDER BY source_dataset;

-- Check 4: Audit required fields for unexpected NULL values
SELECT 
    COUNT(*) FILTER (WHERE transaction_month IS NULL) AS null_dates,
    COUNT(*) FILTER (WHERE town IS NULL)              AS null_towns,
    COUNT(*) FILTER (WHERE flat_type IS NULL)         AS null_flat_types,
    COUNT(*) FILTER (WHERE floor_area_sqm IS NULL)    AS null_floor_areas,
    COUNT(*) FILTER (WHERE resale_price IS NULL)      AS null_resale_prices
FROM staging.hdb_resale_prices;