-- =============================================================================
-- 03 — DATA CLEANING
-- Script:      03_data_cleaning.sql
-- Description: Cleans and standardizes ingested data by addressing missing
--              values, duplicates, inconsistent formats, invalid records,
--              and data type issues.
-- Target DB:   PostgreSQL 16
-- Author:      J.B. Lawrence
-- =============================================================================
-- Ensure search path defaults to analytics and staging schemas
SET search_path TO analytics, staging, public;


-- =============================================================================
-- STEP 1: CREATE ANALYTICAL TRANSACTION FACT VIEW
-- =============================================================================

DROP VIEW IF EXISTS analytics.fct_resale_transactions CASCADE;

CREATE VIEW analytics.fct_resale_transactions AS
WITH raw_parsed AS (
    SELECT 
        resale_id,
        transaction_month,
        
        -- ---------------------------------------------------------------------
        -- 1. Categorical Normalization (Capitalization, Whitespace & Mapping)
        -- ---------------------------------------------------------------------
        UPPER(TRIM(town)) AS town,
        
        -- Normalize flat_type to standard compound hyphenated form
        CASE 
            WHEN UPPER(TRIM(flat_type)) IN ('MULTI GENERATION', 'MULTI-GENERATION') THEN 'MULTI-GENERATION'
            ELSE UPPER(TRIM(flat_type))
        END AS flat_type,
        
        UPPER(TRIM(flat_model)) AS flat_model,
        UPPER(TRIM(street_name)) AS street_name,
        TRIM(block) AS block,
        
        -- ---------------------------------------------------------------------
        -- 2. Storey Range Coordinates
        -- ---------------------------------------------------------------------
        storey_range,
        SPLIT_PART(storey_range, ' TO ', 1)::NUMERIC AS floor_range_min,
        SPLIT_PART(storey_range, ' TO ', 2)::NUMERIC AS floor_range_max,
        (
            SPLIT_PART(storey_range, ' TO ', 1)::NUMERIC + 
            SPLIT_PART(storey_range, ' TO ', 2)::NUMERIC
        ) / 2.0 AS floor_midpoint,
        
        -- ---------------------------------------------------------------------
        -- 3. Remaining Lease Standardization (Exact Decimal Years)
        -- ---------------------------------------------------------------------
        remaining_lease,
        (REGEXP_MATCH(remaining_lease, '^(\d+)'))[1]::NUMERIC 
        + 
        COALESCE(
            ((REGEXP_MATCH(remaining_lease, '(\d+)\s*month'))[1]::NUMERIC / 12.0), 
            0
        ) AS remaining_lease_decimal,
        
        -- ---------------------------------------------------------------------
        -- 4. Core Numeric Metrics
        -- ---------------------------------------------------------------------
        floor_area_sqm,
        resale_price,
        
        -- Derived unit price per square meter (Protected against division by zero)
        resale_price / NULLIF(floor_area_sqm, 0) AS price_per_sqm,
        
        -- Source Lineage
        source_dataset,
        lease_commence_date
        
    FROM staging.hdb_resale_prices
),

duplicate_flagged AS (
    SELECT 
        *,
        -- ---------------------------------------------------------------------
        -- 5. Potential Duplicate Detection
        -- ---------------------------------------------------------------------
        -- Flags matching transactions on month, block, street, flat_type, and price
        COUNT(*) OVER (
            PARTITION BY transaction_month, block, street_name, flat_type, resale_price
        ) > 1 AS is_potential_duplicate
    FROM raw_parsed
)

SELECT 
    resale_id,
    
    -- Date & Time Dimensions
    transaction_month,
    EXTRACT(YEAR FROM transaction_month)::INTEGER AS transaction_year,
    EXTRACT(QUARTER FROM transaction_month)::INTEGER AS transaction_quarter,
    EXTRACT(MONTH FROM transaction_month)::INTEGER AS transaction_month_number,
    TO_CHAR(transaction_month, 'YYYY') || '-Q' || EXTRACT(QUARTER FROM transaction_month)::TEXT AS year_quarter_id,
    
    -- Categorical & Location Attributes
    town,
    flat_type,
    flat_model,
    street_name,
    block,
    
    -- Storey Level Attributes
    storey_range,
    floor_range_min,
    floor_range_max,
    floor_midpoint,
    
    -- Structural & Valuation Metrics
    floor_area_sqm,
    resale_price,
    price_per_sqm,
    
    -- Lease Attributes & Segmentation Buckets
    lease_commence_date,
    remaining_lease,
    remaining_lease_decimal,
    CASE 
        WHEN remaining_lease_decimal < 50.0 THEN '< 50 years'
        WHEN remaining_lease_decimal >= 50.0 AND remaining_lease_decimal <= 70.0 THEN '50–70 years'
        WHEN remaining_lease_decimal > 70.0 THEN '> 70 years'
        ELSE 'Uncategorized'
    END AS lease_bucket,
    
    -- Data Quality Indicators & Validation Flags
    (resale_price > 0) AS is_valid_price,
    (floor_area_sqm > 0) AS is_valid_area,
    (remaining_lease_decimal >= 0.0 AND remaining_lease_decimal <= 99.0) AS is_valid_lease,
    (transaction_month IS NOT NULL) AS is_valid_transaction_date,
    is_potential_duplicate,
    
    -- Master Transaction Validity Indicator
    (
        resale_price > 0 
        AND floor_area_sqm > 0 
        AND remaining_lease_decimal >= 0.0 
        AND remaining_lease_decimal <= 99.0 
        AND transaction_month IS NOT NULL
    ) AS is_valid_transaction,
    
    -- Lineage Tracking
    source_dataset

FROM duplicate_flagged;


-- =============================================================================
-- STEP 2: AUDIT & QUALITY ASSURANCE VERIFICATION CHECKS
-- =============================================================================

-- Check 1: Audit Data Validation Flags (Count of invalid records per rule)
SELECT 
    COUNT(*) FILTER (WHERE NOT is_valid_price) AS invalid_price_count,
    COUNT(*) FILTER (WHERE NOT is_valid_area) AS invalid_area_count,
    COUNT(*) FILTER (WHERE NOT is_valid_lease) AS invalid_lease_count,
    COUNT(*) FILTER (WHERE NOT is_valid_transaction_date) AS invalid_date_count,
    COUNT(*) FILTER (WHERE is_potential_duplicate) AS potential_duplicate_count,
    COUNT(*) FILTER (WHERE NOT is_valid_transaction) AS total_invalid_transactions
FROM analytics.fct_resale_transactions;

-- Check 2: Verify Lease Bucket Distribution & Decimal Range
SELECT 
    lease_bucket,
    COUNT(*) AS record_count,
    ROUND(MIN(remaining_lease_decimal), 2) AS min_lease_decimal,
    ROUND(MAX(remaining_lease_decimal), 2) AS max_lease_decimal
FROM analytics.fct_resale_transactions
GROUP BY lease_bucket
ORDER BY min_lease_decimal;

-- Check 3: Verify Storey Range Coordinate Parsing
SELECT 
    storey_range,
    floor_range_min,
    floor_range_max,
    floor_midpoint,
    COUNT(*) AS transaction_count
FROM analytics.fct_resale_transactions
GROUP BY storey_range, floor_range_min, floor_range_max, floor_midpoint
ORDER BY floor_range_min
LIMIT 10;