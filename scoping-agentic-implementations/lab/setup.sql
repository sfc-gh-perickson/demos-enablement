-- =============================================================================
-- Scoping Agentic Implementations: Lab Setup
-- =============================================================================
-- Creates the lab environment for the scoping workshop.
-- Includes: database/schema, eval stage, sample sales data,
-- and an entitlements table for the multi-tenancy scoping exercise.
--
-- Prerequisites: SYSADMIN role (or equivalent with CREATE DATABASE privileges)
-- =============================================================================

USE ROLE SYSADMIN;

-- Create lab infrastructure
CREATE DATABASE IF NOT EXISTS SCOPING_LAB;
CREATE SCHEMA IF NOT EXISTS SCOPING_LAB.PUBLIC;
CREATE WAREHOUSE IF NOT EXISTS SCOPING_LAB_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE DATABASE SCOPING_LAB;
USE SCHEMA PUBLIC;
USE WAREHOUSE SCOPING_LAB_WH;

-- =============================================================================
-- Internal Stage for Eval Config
-- =============================================================================

CREATE STAGE IF NOT EXISTS EVAL_STAGE
    COMMENT = 'Stores evaluation configuration YAML files';

-- =============================================================================
-- Sample Sales Data (Semantic View prerequisite context)
-- =============================================================================

CREATE OR REPLACE TABLE SAMPLE_SALES_DATA (
    DEAL_ID VARCHAR,
    REGION VARCHAR,
    PRODUCT_LINE VARCHAR,
    REVENUE NUMBER(12,2),
    CLOSE_DATE DATE,
    STAGE VARCHAR,
    CUSTOMER_NAME VARCHAR,
    DEAL_SIZE_BUCKET VARCHAR,
    SALES_CYCLE_DAYS NUMBER,
    OWNER_TENANT_ID VARCHAR
);

INSERT INTO SAMPLE_SALES_DATA VALUES
('D001', 'West', 'Enterprise', 4200000.00, '2024-06-15', 'Closed Won', 'Acme Corp', 'Large', 45, 'tenant_west'),
('D002', 'East', 'Mid-Market', 850000.00, '2024-06-20', 'Closed Won', 'Beta Inc', 'Medium', 30, 'tenant_east'),
('D003', 'West', 'Enterprise', 3100000.00, '2024-07-10', 'Closed Won', 'Gamma LLC', 'Large', 60, 'tenant_west'),
('D004', 'Northeast', 'SMB', 120000.00, '2024-07-22', 'Closed Lost', 'Delta Co', 'Small', 25, 'tenant_east'),
('D005', 'South', 'Mid-Market', 950000.00, '2024-08-05', 'Closed Won', 'Epsilon Ltd', 'Medium', 35, 'tenant_south'),
('D006', 'West', 'Enterprise', 5500000.00, '2024-08-18', 'Stage 3', 'Zeta Corp', 'Large', NULL, 'tenant_west'),
('D007', 'East', 'SMB', 200000.00, '2024-09-01', 'Closed Won', 'Eta Inc', 'Small', 20, 'tenant_east'),
('D008', 'Northeast', 'Enterprise', 2800000.00, '2024-09-15', 'Closed Lost', 'Theta Group', 'Large', 90, 'tenant_east'),
('D009', 'South', 'Mid-Market', 1100000.00, '2024-10-01', 'Closed Won', 'Iota LLC', 'Medium', 40, 'tenant_south'),
('D010', 'West', 'Enterprise', 6200000.00, '2024-10-20', 'Stage 4', 'Kappa Corp', 'Large', NULL, 'tenant_west');

-- =============================================================================
-- Entitlements Table (Multi-Tenancy Scoping Exercise)
-- =============================================================================
-- Demonstrates the entitlements pattern: user identity maps to data access
-- without requiring per-user DDL (no roles, grants, or Snowflake accounts).

CREATE OR REPLACE TABLE ENTITLEMENTS (
    TENANT_ID VARCHAR,
    USER_ID VARCHAR,
    USER_NAME VARCHAR,
    ALLOWED_REGION VARCHAR,
    ACCESS_LEVEL VARCHAR,
    SENSITIVE_COLUMNS_VISIBLE BOOLEAN
);

INSERT INTO ENTITLEMENTS VALUES
-- West region team
('tenant_west', 'user_001', 'Alice Manager', 'West', 'full', TRUE),
('tenant_west', 'user_002', 'Bob Rep', 'West', 'read_only', FALSE),
-- East region team
('tenant_east', 'user_003', 'Carol Director', 'East', 'full', TRUE),
('tenant_east', 'user_003', 'Carol Director', 'Northeast', 'full', TRUE),
('tenant_east', 'user_004', 'Dave Rep', 'East', 'read_only', FALSE),
-- South region team
('tenant_south', 'user_005', 'Eve Manager', 'South', 'full', TRUE),
('tenant_south', 'user_006', 'Frank Analyst', 'South', 'read_only', TRUE);

-- =============================================================================
-- Setup Complete
-- =============================================================================
-- Lab environment ready. Proceed to the workshop notebook.
--
-- Resources created:
--   Database: SCOPING_LAB
--   Warehouse: SCOPING_LAB_WH (XS, auto-suspend 60s)
--   Stage: EVAL_STAGE (for eval config YAML)
--   Tables:
--     - SAMPLE_SALES_DATA (with OWNER_TENANT_ID for RAP demo)
--     - ENTITLEMENTS (multi-tenancy user-to-access mapping)
-- =============================================================================
