-- =============================================================================
-- Cortex AI Observability Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, warehouse, unified usage view,
-- and fallback simulated data for accounts without ACCOUNT_USAGE access.
--
-- Prerequisites:
--   - A role with IMPORTED PRIVILEGES on SNOWFLAKE database (for ACCOUNT_USAGE views)
--   - ACCOUNTADMIN or a role with access to SNOWFLAKE.ACCOUNT_USAGE schema
--   - Cross-region inference NOT required for this lab
--   - SNOWFLAKE.CORTEX_USER database role granted to your role (for any Cortex functions)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS OBSERVABILITY_LAB;
USE DATABASE OBSERVABILITY_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS OBSERVABILITY_LAB_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE OBSERVABILITY_LAB_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RBAC CHECK
-- ─────────────────────────────────────────────────────────────────────────────
-- This lab queries SNOWFLAKE.ACCOUNT_USAGE.* views directly:
--   - CORTEX_AGENT_USAGE_HISTORY
--   - SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY
--   - CORTEX_CODE_CLI_USAGE_HISTORY
--   - QUERY_ATTRIBUTION_HISTORY
--
-- If the participant doesn't have access to these views (requires IMPORTED
-- PRIVILEGES on the SNOWFLAKE database), the script creates fallback simulated
-- data in the SIMULATED_AI_USAGE table below. The notebook detects this and
-- uses the simulated data as a substitute.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. UNIFIED AI USAGE VIEW
-- ─────────────────────────────────────────────────────────────────────────────
-- This view normalizes across all Cortex AI usage surfaces into a single
-- queryable interface. Surface identification uses METADATA:interaction_interface
-- from agent usage history.

CREATE OR REPLACE VIEW V_UNIFIED_AI_USAGE AS

-- Cortex Agent Usage (API, MCP, Admin UI, etc.)
SELECT
    CASE
        WHEN METADATA:"interaction_interface"::STRING = 'external' THEN 'EXTERNAL_API'
        WHEN METADATA:"interaction_interface"::STRING = 'sql_function' THEN 'SQL_FUNCTION'
        WHEN METADATA:"interaction_interface"::STRING = 'agent_admin_ui' THEN 'AGENT_ADMIN_UI'
        WHEN METADATA:"interaction_interface"::STRING = 'rest_api' THEN 'REST_API'
        ELSE COALESCE(METADATA:"interaction_interface"::STRING, 'UNKNOWN')
    END AS SURFACE,
    USER_NAME,
    AGENT_NAME,
    METADATA:"interaction_interface"::STRING AS INTERFACE,
    TOKENS,
    TOKEN_CREDITS,
    REQUEST_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY

UNION ALL

-- Snowflake Intelligence (CoWork) Usage
SELECT
    'COWORK' AS SURFACE,
    USER_NAME,
    SNOWFLAKE_INTELLIGENCE_NAME AS AGENT_NAME,
    'cowork' AS INTERFACE,
    TOKENS,
    TOKEN_CREDITS,
    REQUEST_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY

UNION ALL

-- Cortex Code CLI Usage
SELECT
    'CORTEX_CODE_CLI' AS SURFACE,
    USER_NAME,
    NULL AS AGENT_NAME,
    'cortex_code_cli' AS INTERFACE,
    TOKENS,
    TOKEN_CREDITS,
    REQUEST_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_CLI_USAGE_HISTORY;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. FALLBACK SIMULATED DATA
-- ─────────────────────────────────────────────────────────────────────────────
-- ~200 rows of realistic usage data spanning 30 days, covering 5 users,
-- 3 agents, and 4 interface types. Used when ACCOUNT_USAGE access is unavailable.

CREATE OR REPLACE TABLE SIMULATED_AI_USAGE (
    SURFACE         VARCHAR,
    USER_NAME       VARCHAR,
    AGENT_NAME      VARCHAR,
    INTERFACE       VARCHAR,
    TOKENS          NUMBER,
    TOKEN_CREDITS   NUMBER(10, 4),
    REQUEST_TIMESTAMP TIMESTAMP_LTZ,
    USER_TAGS       VARIANT,
    AGENT_TAGS      VARIANT
);

-- Generate realistic simulated data
-- Users: ALICE_SMITH, BOB_JONES, CAROL_CHEN, DAVE_PATEL, EVE_GARCIA
-- Agents: SALES_ASSISTANT, DATA_ANALYST_BOT, CUSTOMER_SUPPORT_AGENT
-- Interfaces: external, sql_function, agent_admin_ui, cowork
-- Pattern: more usage on weekdays, external interface most common

INSERT INTO SIMULATED_AI_USAGE VALUES
-- Week 1 (Mon-Fri) - Heavy external API usage
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 45200, 0.0542, '2024-11-04 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 38100, 0.0457, '2024-11-04 10:32:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'BOB_JONES', 'DATA_ANALYST_BOT', 'sql_function', 125000, 0.1500, '2024-11-04 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 67800, 0.0814, '2024-11-04 13:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'DAVE_PATEL', 'SALES_ASSISTANT', 'agent_admin_ui', 12500, 0.0150, '2024-11-04 14:20:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 89000, 0.1068, '2024-11-04 15:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 52300, 0.0628, '2024-11-05 08:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 187000, 0.2244, '2024-11-05 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 95400, 0.1145, '2024-11-05 10:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 145000, 0.1740, '2024-11-05 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 78200, 0.0938, '2024-11-05 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'CUSTOMER_SUPPORT_AGENT', 'external', 34500, 0.0414, '2024-11-05 16:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 210000, 0.2520, '2024-11-06 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'ALICE_SMITH', 'SALES_ASSISTANT', 'sql_function', 28900, 0.0347, '2024-11-06 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 156000, 0.1872, '2024-11-06 10:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 112000, 0.1344, '2024-11-06 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('AGENT_ADMIN_UI', 'BOB_JONES', 'DATA_ANALYST_BOT', 'agent_admin_ui', 8700, 0.0104, '2024-11-06 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 67200, 0.0806, '2024-11-06 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 41800, 0.0502, '2024-11-07 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'BOB_JONES', 'DATA_ANALYST_BOT', 'sql_function', 198000, 0.2376, '2024-11-07 09:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 73500, 0.0882, '2024-11-07 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 56000, 0.0672, '2024-11-07 11:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 134000, 0.1608, '2024-11-07 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('AGENT_ADMIN_UI', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'agent_admin_ui', 15200, 0.0182, '2024-11-07 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 245000, 0.2940, '2024-11-08 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 89100, 0.1069, '2024-11-08 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('SQL_FUNCTION', 'ALICE_SMITH', 'SALES_ASSISTANT', 'sql_function', 31200, 0.0374, '2024-11-08 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 167000, 0.2004, '2024-11-08 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 53800, 0.0646, '2024-11-08 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),

-- Weekend (Sat-Sun) - Lighter usage
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 23000, 0.0276, '2024-11-09 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 45000, 0.0540, '2024-11-09 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 12000, 0.0144, '2024-11-10 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),

-- Week 2 (Mon-Fri)
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 62100, 0.0745, '2024-11-11 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 178000, 0.2136, '2024-11-11 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 102000, 0.1224, '2024-11-11 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 134000, 0.1608, '2024-11-11 11:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 91000, 0.1092, '2024-11-11 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('AGENT_ADMIN_UI', 'ALICE_SMITH', 'SALES_ASSISTANT', 'agent_admin_ui', 9800, 0.0118, '2024-11-11 16:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 223000, 0.2676, '2024-11-12 08:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 48700, 0.0584, '2024-11-12 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 156000, 0.1872, '2024-11-12 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'CAROL_CHEN', NULL, 'cowork', 78000, 0.0936, '2024-11-12 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), NULL),
('EXTERNAL_API', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'external', 87600, 0.1051, '2024-11-12 13:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 195000, 0.2340, '2024-11-13 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 143000, 0.1716, '2024-11-13 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 67000, 0.0804, '2024-11-13 10:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('SQL_FUNCTION', 'DAVE_PATEL', 'SALES_ASSISTANT', 'sql_function', 34500, 0.0414, '2024-11-13 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'EVE_GARCIA', 'CUSTOMER_SUPPORT_AGENT', 'external', 108000, 0.1296, '2024-11-13 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'BOB_JONES', 'DATA_ANALYST_BOT', 'agent_admin_ui', 11200, 0.0134, '2024-11-13 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 57400, 0.0689, '2024-11-14 08:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 234000, 0.2808, '2024-11-14 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'CAROL_CHEN', NULL, 'cowork', 92000, 0.1104, '2024-11-14 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), NULL),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 71300, 0.0856, '2024-11-14 11:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 167000, 0.2004, '2024-11-14 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 128000, 0.1536, '2024-11-14 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 39800, 0.0478, '2024-11-15 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 201000, 0.2412, '2024-11-15 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 145000, 0.1740, '2024-11-15 10:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 87000, 0.1044, '2024-11-15 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'DAVE_PATEL', 'SALES_ASSISTANT', 'agent_admin_ui', 14300, 0.0172, '2024-11-15 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'external', 96500, 0.1158, '2024-11-15 14:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),

-- Weekend (Sat-Sun) - Very light
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 34000, 0.0408, '2024-11-16 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'BOB_JONES', NULL, 'cowork', 28000, 0.0336, '2024-11-17 12:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), NULL),

-- Week 3 (Mon-Fri)
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 71200, 0.0854, '2024-11-18 08:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 189000, 0.2268, '2024-11-18 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 115000, 0.1380, '2024-11-18 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 98000, 0.1176, '2024-11-18 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'SALES_ASSISTANT', 'external', 56700, 0.0680, '2024-11-18 13:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('AGENT_ADMIN_UI', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'agent_admin_ui', 7500, 0.0090, '2024-11-18 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 83400, 0.1001, '2024-11-19 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 215000, 0.2580, '2024-11-19 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'DAVE_PATEL', 'SALES_ASSISTANT', 'sql_function', 42000, 0.0504, '2024-11-19 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 123000, 0.1476, '2024-11-19 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 167000, 0.2004, '2024-11-19 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'CUSTOMER_SUPPORT_AGENT', 'external', 29800, 0.0358, '2024-11-19 16:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 248000, 0.2976, '2024-11-20 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 78900, 0.0947, '2024-11-20 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'CAROL_CHEN', NULL, 'cowork', 85000, 0.1020, '2024-11-20 10:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), NULL),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 178000, 0.2136, '2024-11-20 11:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 63200, 0.0758, '2024-11-20 13:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('AGENT_ADMIN_UI', 'BOB_JONES', 'DATA_ANALYST_BOT', 'agent_admin_ui', 13100, 0.0157, '2024-11-20 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 134000, 0.1608, '2024-11-21 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 47600, 0.0571, '2024-11-21 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'BOB_JONES', 'DATA_ANALYST_BOT', 'sql_function', 205000, 0.2460, '2024-11-21 09:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 110000, 0.1320, '2024-11-21 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'CUSTOMER_SUPPORT_AGENT', 'external', 94500, 0.1134, '2024-11-21 13:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'ALICE_SMITH', 'SALES_ASSISTANT', 'agent_admin_ui', 10500, 0.0126, '2024-11-21 14:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 82100, 0.0985, '2024-11-21 15:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 176000, 0.2112, '2024-11-22 08:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 119000, 0.1428, '2024-11-22 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 54000, 0.0648, '2024-11-22 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 143000, 0.1716, '2024-11-22 11:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'external', 65800, 0.0790, '2024-11-22 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),

-- Weekend
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 52000, 0.0624, '2024-11-23 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 31000, 0.0372, '2024-11-24 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),

-- Week 4 (Mon-Fri) - End of month push, heavier usage
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 95200, 0.1142, '2024-11-25 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 230000, 0.2760, '2024-11-25 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 132000, 0.1584, '2024-11-25 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 156000, 0.1872, '2024-11-25 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 187000, 0.2244, '2024-11-25 11:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'SALES_ASSISTANT', 'external', 54300, 0.0652, '2024-11-25 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('AGENT_ADMIN_UI', 'ALICE_SMITH', 'CUSTOMER_SUPPORT_AGENT', 'agent_admin_ui', 16800, 0.0202, '2024-11-25 15:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 250000, 0.3000, '2024-11-26 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 88700, 0.1064, '2024-11-26 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('SQL_FUNCTION', 'DAVE_PATEL', 'SALES_ASSISTANT', 'sql_function', 47800, 0.0574, '2024-11-26 09:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'CAROL_CHEN', NULL, 'cowork', 103000, 0.1236, '2024-11-26 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'CUSTOMER_SUPPORT_AGENT', 'external', 142000, 0.1704, '2024-11-26 11:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 102000, 0.1224, '2024-11-26 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('AGENT_ADMIN_UI', 'BOB_JONES', 'DATA_ANALYST_BOT', 'agent_admin_ui', 18900, 0.0227, '2024-11-26 15:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 105000, 0.1260, '2024-11-27 08:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 220000, 0.2640, '2024-11-27 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'EVE_GARCIA', NULL, 'cowork', 178000, 0.2136, '2024-11-27 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), NULL),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 145000, 0.1740, '2024-11-27 10:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'external', 113000, 0.1356, '2024-11-27 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'SALES_ASSISTANT', 'external', 67400, 0.0809, '2024-11-27 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 112000, 0.1344, '2024-11-28 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 241000, 0.2892, '2024-11-28 08:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 192000, 0.2304, '2024-11-28 09:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 72000, 0.0864, '2024-11-28 10:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 158000, 0.1896, '2024-11-28 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'DAVE_PATEL', 'SALES_ASSISTANT', 'agent_admin_ui', 21000, 0.0252, '2024-11-28 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 118000, 0.1416, '2024-11-28 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'EVE_GARCIA', 'CUSTOMER_SUPPORT_AGENT', 'external', 76500, 0.0918, '2024-11-28 15:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 198000, 0.2376, '2024-11-29 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 79300, 0.0952, '2024-11-29 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('COWORK', 'CAROL_CHEN', NULL, 'cowork', 95000, 0.1140, '2024-11-29 10:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), NULL),
('SQL_FUNCTION', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 88000, 0.1056, '2024-11-29 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 165000, 0.1980, '2024-11-29 13:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('AGENT_ADMIN_UI', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'agent_admin_ui', 19500, 0.0234, '2024-11-29 14:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'SALES_ASSISTANT', 'external', 45600, 0.0547, '2024-11-29 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),

-- Weekend / Month end
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 41000, 0.0492, '2024-11-30 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 87000, 0.1044, '2024-11-30 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'external', 56000, 0.0672, '2024-12-01 15:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),

-- First days of December (Week 5 partial)
('EXTERNAL_API', 'ALICE_SMITH', 'SALES_ASSISTANT', 'external', 98000, 0.1176, '2024-12-02 08:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 215000, 0.2580, '2024-12-02 09:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('SQL_FUNCTION', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'sql_function', 124000, 0.1488, '2024-12-02 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'DAVE_PATEL', NULL, 'cowork', 142000, 0.1704, '2024-12-02 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('EXTERNAL_API', 'EVE_GARCIA', 'SALES_ASSISTANT', 'external', 73200, 0.0878, '2024-12-02 13:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'CUSTOMER_SUPPORT_AGENT', 'external', 108500, 0.1302, '2024-12-02 14:45:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'ALICE_SMITH', 'SALES_ASSISTANT', 'agent_admin_ui', 12400, 0.0149, '2024-12-02 16:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'BOB_JONES', 'DATA_ANALYST_BOT', 'external', 238000, 0.2856, '2024-12-03 08:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'CAROL_CHEN', 'CUSTOMER_SUPPORT_AGENT', 'external', 147000, 0.1764, '2024-12-03 09:15:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "customer-success"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('COWORK', 'ALICE_SMITH', NULL, 'cowork', 89000, 0.1068, '2024-12-03 10:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), NULL),
('SQL_FUNCTION', 'EVE_GARCIA', 'DATA_ANALYST_BOT', 'sql_function', 183000, 0.2196, '2024-12-03 11:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "product"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]')),
('EXTERNAL_API', 'DAVE_PATEL', 'SALES_ASSISTANT', 'external', 91400, 0.1097, '2024-12-03 13:00:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "revenue"} ]')),
('EXTERNAL_API', 'ALICE_SMITH', 'CUSTOMER_SUPPORT_AGENT', 'external', 56700, 0.0680, '2024-12-03 14:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "sales-ops"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "support"} ]')),
('AGENT_ADMIN_UI', 'BOB_JONES', 'DATA_ANALYST_BOT', 'agent_admin_ui', 15700, 0.0188, '2024-12-03 15:30:00 -0800'::TIMESTAMP_LTZ, PARSE_JSON('[ {"tag_name": "cost-center", "tag_value": "data-engineering"} ]'), PARSE_JSON('[ {"tag_name": "team", "tag_value": "platform"} ]'));

-- Verify row count
SELECT COUNT(*) AS SIMULATED_ROW_COUNT FROM SIMULATED_AI_USAGE;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify objects were created:
SHOW TABLES IN SCHEMA OBSERVABILITY_LAB.PUBLIC;
SHOW VIEWS IN SCHEMA OBSERVABILITY_LAB.PUBLIC;
