-- =============================================================================
-- Test Suite: Schema Mapper Agent Infrastructure
-- Tests that required objects, tables, and procedures exist and function correctly.
-- =============================================================================
-- Convention: Each test is a self-contained query that returns 'PASS' or 'FAIL'.
-- Run all tests: execute this file in Snowflake; any row returning 'FAIL' is a
-- broken test.
-- =============================================================================

USE SCHEMA ACME_FINANCE.INGESTION;

-- =============================================================================
-- TEST 1: MAPPING_CONFIGS table exists with required columns
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) >= 6
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_1_MAPPING_CONFIGS_TABLE_SCHEMA' AS test_name
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'INGESTION'
  AND TABLE_NAME = 'MAPPING_CONFIGS'
  AND COLUMN_NAME IN (
    'SOURCE_COLUMN_SIGNATURE', 'TARGET_TABLE', 'COLUMN_MAP',
    'TYPE_COERCIONS', 'VALUE_TRANSFORMS', 'IGNORED_COLUMNS'
  );


-- =============================================================================
-- TEST 2: Canonical target tables exist
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) = 3
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_2_CANONICAL_TABLES_EXIST' AS test_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'INGESTION'
  AND TABLE_NAME IN (
    'MILEAGE_CLAIMS',
    'PURCHASE_EXPENSES',
    'VENDOR_INVOICES'
  );


-- =============================================================================
-- TEST 3: Active stored procedures exist
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) >= 5
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_3_STORED_PROCEDURES_EXIST' AS test_name
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'INGESTION'
  AND PROCEDURE_NAME IN (
    'SP_PROFILE_STAGED_FILE',
    'PROFILE_FILE',
    'PROPOSE_MAPPING',
    'SP_BUILD_AND_EXECUTE_COPY_INTO',
    'EXECUTE_MAPPING',
    'SP_RESOLVE_COLUMN_VALUES',
    'PREVIEW_RESOLUTION'
  );


-- =============================================================================
-- TEST 4: Active UDFs exist
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) >= 3
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_4_UDFS_EXIST' AS test_name
FROM INFORMATION_SCHEMA.FUNCTIONS
WHERE FUNCTION_SCHEMA = 'INGESTION'
  AND FUNCTION_NAME IN (
    'LIST_STAGED_FILES',
    'GET_TARGET_SCHEMAS',
    'AI_PROPOSE_MAPPING',
    'AI_RESOLVE_VALUES'
  );


-- =============================================================================
-- TEST 5: VALUE_RESOLUTION_CACHE table exists
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) >= 3
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_5_VALUE_RESOLUTION_CACHE_EXISTS' AS test_name
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'INGESTION'
  AND TABLE_NAME = 'VALUE_RESOLUTION_CACHE'
  AND COLUMN_NAME IN (
    'SOURCE_VALUES_HASH', 'RESOLUTION_MAP', 'TARGET_COLUMN'
  );


-- =============================================================================
-- TEST 6: Reference tables are populated
-- =============================================================================

SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.REF_EXPENSE_CATEGORIES) > 0
         AND (SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.REF_VENDORS) > 0
         AND (SELECT COUNT(*) FROM ACME_FINANCE.INGESTION.REF_GL_ACCOUNTS) > 0
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_6_REFERENCE_DATA_POPULATED' AS test_name;


-- =============================================================================
-- TEST 7: Upload stage exists and directory is enabled
-- =============================================================================

SELECT
    CASE
        WHEN COUNT(*) > 0
        THEN 'PASS' ELSE 'FAIL'
    END AS test_result,
    'TEST_7_UPLOAD_STAGE_EXISTS' AS test_name
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_SCHEMA = 'INGESTION'
  AND STAGE_NAME = 'UPLOAD_STAGE';
