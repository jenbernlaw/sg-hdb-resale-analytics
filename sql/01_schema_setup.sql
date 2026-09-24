-- =============================================================================
-- 01 — SCHEMA SETUP
-- Script:      01_schema_setup.sql
-- Description: Defines the database schemas and table structures used throughout
--              the project, including data types, keys, and table relationships.
-- Target DB:   PostgreSQL 16
-- Author:      J.B. Lawrence
-- =============================================================================

-- Database and Schema Setup for Data.gov.sg HDB Resale Dataset (2015–Present)

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;


-- 2. Define Raw Tables (Exact CSV Structure, Text/Unprocessed Types)
-- Used only as temporary staging ground during CSV COPY/import operations

CREATE TABLE IF NOT EXISTS raw.hdb_resale_2015_2016 (
    month               VARCHAR(10),
    town                VARCHAR(50),
    flat_type           VARCHAR(20),
    block               VARCHAR(20),
    street_name         VARCHAR(150),
    storey_range        VARCHAR(20),
    floor_area_sqm      NUMERIC(8, 2),
    flat_model          VARCHAR(50),
    lease_commence_date INTEGER,
    remaining_lease     VARCHAR(50),
    resale_price        NUMERIC(12, 2)
);

CREATE TABLE IF NOT EXISTS raw.hdb_resale_2017_present (
    month               VARCHAR(10),
    town                VARCHAR(50),
    flat_type           VARCHAR(20),
    block               VARCHAR(20),
    street_name         VARCHAR(150),
    storey_range        VARCHAR(20),
    floor_area_sqm      NUMERIC(8, 2),
    flat_model          VARCHAR(50),
    lease_commence_date INTEGER,
    remaining_lease     VARCHAR(50),
    resale_price        NUMERIC(12, 2)
);


-- 3. Define Consolidated Staging Table (Cleaned, Standardized Data Types)

CREATE TABLE IF NOT EXISTS staging.hdb_resale_prices (
    resale_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_month   DATE NOT NULL,
    town                VARCHAR(50) NOT NULL,
    flat_type           VARCHAR(20) NOT NULL,
    block               VARCHAR(20) NOT NULL,
    street_name         VARCHAR(150) NOT NULL,
    storey_range        VARCHAR(20) NOT NULL,
    floor_area_sqm      NUMERIC(8, 2) NOT NULL,
    flat_model          VARCHAR(50) NOT NULL,
    lease_commence_date INTEGER NOT NULL,
    remaining_lease     VARCHAR(50) NOT NULL,
    resale_price        NUMERIC(12, 2) NOT NULL,
    source_dataset      VARCHAR(50) NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


-- 4. Indexing Strategy on Staging Table

CREATE INDEX idx_staging_hdb_town_type_month 
ON staging.hdb_resale_prices (town, flat_type, transaction_month);

CREATE INDEX idx_staging_hdb_transaction_month 
ON staging.hdb_resale_prices (transaction_month DESC);

