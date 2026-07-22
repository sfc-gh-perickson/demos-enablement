-- =============================================================================
-- Cortex Agent Document Context Lab: Setup Script
-- =============================================================================
-- Run this script as ACCOUNTADMIN (or a role with CREATE DATABASE privileges)
-- before starting the lab notebook.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1. DATABASE, SCHEMA, WAREHOUSE
-- -----------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS DOCUMENT_CONTEXT_LAB;
USE DATABASE DOCUMENT_CONTEXT_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

CREATE WAREHOUSE IF NOT EXISTS DOCUMENT_CONTEXT_LAB_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE WAREHOUSE DOCUMENT_CONTEXT_LAB_WH;

-- -----------------------------------------------------------------------------
-- 2. INTERNAL STAGE FOR DOCUMENT UPLOADS
-- -----------------------------------------------------------------------------

CREATE OR REPLACE STAGE DOC_UPLOADS
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- -----------------------------------------------------------------------------
-- 3. STORE PERFORMANCE DATA
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE STORE_PERFORMANCE (
    STORE_ID        VARCHAR,
    STORE_NAME      VARCHAR,
    REGION          VARCHAR,
    STATE           VARCHAR,
    MONTH           DATE,
    REVENUE         NUMBER(12,2),
    LABOR_COST      NUMBER(12,2),
    FOOD_COST       NUMBER(12,2),
    CUSTOMER_COUNT  NUMBER,
    AVG_TICKET      NUMBER(8,2),
    DRIVE_THRU_PCT  NUMBER(5,2),
    DIGITAL_PCT     NUMBER(5,2)
);

INSERT INTO STORE_PERFORMANCE VALUES
-- Northeast region
('FB-101', 'FreshBite Times Square',    'Northeast', 'NY', '2024-01-01', 485000.00, 145500.00, 155200.00, 32000, 15.16, 12.5, 38.2),
('FB-101', 'FreshBite Times Square',    'Northeast', 'NY', '2024-02-01', 462000.00, 138600.00, 147840.00, 30500, 15.15, 11.8, 39.1),
('FB-101', 'FreshBite Times Square',    'Northeast', 'NY', '2024-03-01', 510000.00, 153000.00, 163200.00, 33800, 15.09, 13.1, 40.5),
('FB-102', 'FreshBite Boston Common',   'Northeast', 'MA', '2024-01-01', 320000.00, 96000.00, 102400.00, 21500, 14.88, 22.0, 35.6),
('FB-102', 'FreshBite Boston Common',   'Northeast', 'MA', '2024-02-01', 298000.00, 89400.00,  95360.00, 19800, 15.05, 21.5, 36.2),
('FB-102', 'FreshBite Boston Common',   'Northeast', 'MA', '2024-03-01', 345000.00, 103500.00, 110400.00, 23000, 15.00, 23.1, 37.8),
('FB-103', 'FreshBite Philly Market',   'Northeast', 'PA', '2024-01-01', 275000.00, 82500.00,  88000.00, 19200, 14.32, 28.5, 30.1),
('FB-103', 'FreshBite Philly Market',   'Northeast', 'PA', '2024-02-01', 260000.00, 78000.00,  83200.00, 18100, 14.36, 27.8, 31.4),
('FB-103', 'FreshBite Philly Market',   'Northeast', 'PA', '2024-03-01', 290000.00, 87000.00,  92800.00, 20300, 14.29, 29.2, 32.0),

-- Southeast region
('FB-201', 'FreshBite Miami Beach',     'Southeast', 'FL', '2024-01-01', 395000.00, 118500.00, 126400.00, 26800, 14.74, 35.0, 42.1),
('FB-201', 'FreshBite Miami Beach',     'Southeast', 'FL', '2024-02-01', 410000.00, 123000.00, 131200.00, 27900, 14.70, 36.2, 43.5),
('FB-201', 'FreshBite Miami Beach',     'Southeast', 'FL', '2024-03-01', 425000.00, 127500.00, 136000.00, 28700, 14.81, 37.1, 44.0),
('FB-202', 'FreshBite Atlanta Midtown', 'Southeast', 'GA', '2024-01-01', 310000.00, 93000.00,  99200.00, 21800, 14.22, 40.5, 33.8),
('FB-202', 'FreshBite Atlanta Midtown', 'Southeast', 'GA', '2024-02-01', 305000.00, 91500.00,  97600.00, 21400, 14.25, 41.0, 34.5),
('FB-202', 'FreshBite Atlanta Midtown', 'Southeast', 'GA', '2024-03-01', 330000.00, 99000.00, 105600.00, 23100, 14.29, 42.3, 35.2),
('FB-203', 'FreshBite Nashville Strip', 'Southeast', 'TN', '2024-01-01', 285000.00, 85500.00,  91200.00, 20100, 14.18, 38.2, 28.5),
('FB-203', 'FreshBite Nashville Strip', 'Southeast', 'TN', '2024-02-01', 292000.00, 87600.00,  93440.00, 20600, 14.17, 39.0, 29.1),
('FB-203', 'FreshBite Nashville Strip', 'Southeast', 'TN', '2024-03-01', 315000.00, 94500.00, 100800.00, 22000, 14.32, 40.5, 30.8),

-- Midwest region
('FB-301', 'FreshBite Chicago Loop',    'Midwest',   'IL', '2024-01-01', 360000.00, 108000.00, 115200.00, 24500, 14.69, 18.0, 36.5),
('FB-301', 'FreshBite Chicago Loop',    'Midwest',   'IL', '2024-02-01', 340000.00, 102000.00, 108800.00, 23000, 14.78, 17.2, 37.0),
('FB-301', 'FreshBite Chicago Loop',    'Midwest',   'IL', '2024-03-01', 380000.00, 114000.00, 121600.00, 25800, 14.73, 19.5, 38.2),
('FB-302', 'FreshBite Detroit Center',  'Midwest',   'MI', '2024-01-01', 245000.00, 73500.00,  78400.00, 17500, 14.00, 45.0, 25.8),
('FB-302', 'FreshBite Detroit Center',  'Midwest',   'MI', '2024-02-01', 238000.00, 71400.00,  76160.00, 17000, 14.00, 44.5, 26.2),
('FB-302', 'FreshBite Detroit Center',  'Midwest',   'MI', '2024-03-01', 262000.00, 78600.00,  83840.00, 18700, 14.01, 46.2, 27.5),

-- West region
('FB-401', 'FreshBite Santa Monica',    'West',      'CA', '2024-01-01', 420000.00, 134400.00, 134400.00, 27000, 15.56, 30.0, 48.2),
('FB-401', 'FreshBite Santa Monica',    'West',      'CA', '2024-02-01', 435000.00, 139200.00, 139200.00, 28000, 15.54, 31.5, 49.0),
('FB-401', 'FreshBite Santa Monica',    'West',      'CA', '2024-03-01', 450000.00, 144000.00, 144000.00, 29000, 15.52, 32.0, 50.5),
('FB-402', 'FreshBite Seattle Pike',    'West',      'WA', '2024-01-01', 305000.00, 91500.00,  97600.00, 20800, 14.66, 25.0, 41.0),
('FB-402', 'FreshBite Seattle Pike',    'West',      'WA', '2024-02-01', 295000.00, 88500.00,  94400.00, 20100, 14.68, 24.5, 41.8),
('FB-402', 'FreshBite Seattle Pike',    'West',      'WA', '2024-03-01', 320000.00, 96000.00, 102400.00, 21800, 14.68, 26.2, 43.0),
('FB-403', 'FreshBite Denver Union',    'West',      'CO', '2024-01-01', 265000.00, 79500.00,  84800.00, 18500, 14.32, 35.0, 32.5),
('FB-403', 'FreshBite Denver Union',    'West',      'CO', '2024-02-01', 258000.00, 77400.00,  82560.00, 18000, 14.33, 34.2, 33.0),
('FB-403', 'FreshBite Denver Union',    'West',      'CO', '2024-03-01', 278000.00, 83400.00,  88960.00, 19400, 14.33, 36.5, 34.2);

-- -----------------------------------------------------------------------------
-- 4. SEMANTIC VIEW
-- -----------------------------------------------------------------------------

CREATE OR REPLACE SEMANTIC VIEW STORE_ANALYTICS
    TABLES (
        STORE_PERFORMANCE AS DOCUMENT_CONTEXT_LAB.PUBLIC.STORE_PERFORMANCE
    )
    DIMENSIONS (
        STORE_PERFORMANCE.STORE_ID AS STORE_ID
            COMMENT = 'Unique store identifier (e.g. FB-101)',
        STORE_PERFORMANCE.STORE_NAME AS STORE_NAME
            COMMENT = 'Full store name including location',
        STORE_PERFORMANCE.REGION AS REGION
            COMMENT = 'Geographic region: Northeast, Southeast, Midwest, or West',
        STORE_PERFORMANCE.STATE AS STATE
            COMMENT = 'US state abbreviation',
        STORE_PERFORMANCE.MONTH AS MONTH
            COMMENT = 'First day of the reporting month'
    )
    METRICS (
        STORE_PERFORMANCE.TOTAL_REVENUE AS SUM(REVENUE)
            COMMENT = 'Total revenue in USD',
        STORE_PERFORMANCE.TOTAL_LABOR_COST AS SUM(LABOR_COST)
            COMMENT = 'Total labor cost in USD',
        STORE_PERFORMANCE.TOTAL_FOOD_COST AS SUM(FOOD_COST)
            COMMENT = 'Total food cost in USD',
        STORE_PERFORMANCE.TOTAL_CUSTOMERS AS SUM(CUSTOMER_COUNT)
            COMMENT = 'Total customer transactions',
        STORE_PERFORMANCE.AVG_TICKET_SIZE AS AVG(AVG_TICKET)
            COMMENT = 'Average ticket size in USD',
        STORE_PERFORMANCE.AVG_DRIVE_THRU AS AVG(DRIVE_THRU_PCT)
            COMMENT = 'Average drive-thru percentage of orders',
        STORE_PERFORMANCE.AVG_DIGITAL AS AVG(DIGITAL_PCT)
            COMMENT = 'Average digital ordering percentage'
    )
    COMMENT = 'FreshBite store performance analytics for BiteIQ agent'
    AI_SQL_GENERATION 'This table contains monthly performance data for FreshBite QSR restaurant locations. Revenue, labor cost, and food cost are in USD. Drive-thru and digital percentages represent the share of orders through those channels. When no date filter is specified, include all available months (Q1 2024). Round currency to 2 decimal places.';

-- -----------------------------------------------------------------------------
-- 5. FILE FORMAT (for direct stage reads if needed outside the UDF)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FILE FORMAT RAW_TEXT_FMT
    TYPE = 'CSV'
    FIELD_DELIMITER = NONE
    RECORD_DELIMITER = '\n';

-- -----------------------------------------------------------------------------
-- 6. UDF: READ_STAGED_DOCUMENT
-- -----------------------------------------------------------------------------
-- SQL UDF that reads a file from DOC_UPLOADS using AI_PARSE_DOCUMENT (LAYOUT mode).
-- Supports: PDF, DOCX, PPTX, TXT, HTML, JPEG, PNG, TIF
-- For CSV/JSON data: upload as .txt so AI_PARSE_DOCUMENT can read it.
-- The middleware should rename .csv/.json to .txt before staging.

CREATE OR REPLACE FUNCTION READ_STAGED_DOCUMENT(filename VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    SELECT COALESCE(
        AI_PARSE_DOCUMENT(
            TO_FILE('@DOCUMENT_CONTEXT_LAB.PUBLIC.DOC_UPLOADS', filename),
            {'mode': 'LAYOUT'}
        ):content::VARCHAR,
        '[Error: Could not parse document]'
    )
$$;

-- -----------------------------------------------------------------------------
-- 7. CORTEX AGENT
-- -----------------------------------------------------------------------------

CREATE OR REPLACE AGENT BITEIQ_AGENT
    COMMENT = 'FreshBite executive insights agent with document context support'
FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    You are BiteIQ, the executive insights assistant for FreshBite, a quick-service
    restaurant chain. Answer questions about store performance, revenue, costs, and
    operational metrics. Be concise and data-driven.

    When a user has uploaded a document, use the read_document tool to access its
    contents. Combine insights from uploaded documents with structured data when relevant.

    Present currency values with $ prefix and 2 decimal places.
    When comparing stores or regions, present results in a clear table format.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "store_analytics"
      description: "Query FreshBite store performance data including revenue, costs, customer counts, average ticket size, drive-thru percentage, and digital ordering percentage. Use for any quantitative question about store or regional metrics."
  - tool_spec:
      type: "generic"
      name: "read_document"
      description: "Read and parse a document that a user has uploaded to the document stage. Call this when the user has uploaded a file and you need its contents. Supports PDF, DOCX, PPTX, TXT, CSV, JSON, and image files."
      input_schema:
        type: object
        properties:
          filename:
            type: string
            description: "The relative path of the file on the upload stage (e.g. 'reports/market_research.txt')"
        required:
          - filename

tool_resources:
  store_analytics:
    semantic_view: "DOCUMENT_CONTEXT_LAB.PUBLIC.STORE_ANALYTICS"
    execution_environment:
      type: warehouse
      warehouse: DOCUMENT_CONTEXT_LAB_WH
  read_document:
    type: function
    identifier: "DOCUMENT_CONTEXT_LAB.PUBLIC.READ_STAGED_DOCUMENT"
    execution_environment:
      type: warehouse
      warehouse: DOCUMENT_CONTEXT_LAB_WH
$$;

-- -----------------------------------------------------------------------------
-- 8. GRANTS
-- -----------------------------------------------------------------------------

GRANT USAGE ON DATABASE DOCUMENT_CONTEXT_LAB TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA DOCUMENT_CONTEXT_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA DOCUMENT_CONTEXT_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT READ ON STAGE DOCUMENT_CONTEXT_LAB.PUBLIC.DOC_UPLOADS TO ROLE SYSADMIN;
GRANT WRITE ON STAGE DOCUMENT_CONTEXT_LAB.PUBLIC.DOC_UPLOADS TO ROLE SYSADMIN;

-- -----------------------------------------------------------------------------
-- SETUP COMPLETE
-- -----------------------------------------------------------------------------
-- After running this script, upload sample docs to stage:
--
--   PUT file://sample-docs/competitive_landscape_q1_2024.txt @DOC_UPLOADS/reports AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://sample-docs/texas_expansion_leases.csv @DOC_UPLOADS/data AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--   PUT file://sample-docs/q2_board_summary.pdf @DOC_UPLOADS/reports AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--
-- Or from the notebook: session.file.put('sample-docs/q2_board_summary.pdf', '@DOC_UPLOADS/reports', auto_compress=False)
-- -----------------------------------------------------------------------------

SHOW TABLES IN SCHEMA DOCUMENT_CONTEXT_LAB.PUBLIC;
SHOW STAGES IN SCHEMA DOCUMENT_CONTEXT_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA DOCUMENT_CONTEXT_LAB.PUBLIC;

SELECT 'Setup complete. Lab objects created in DOCUMENT_CONTEXT_LAB database.' AS STATUS;
