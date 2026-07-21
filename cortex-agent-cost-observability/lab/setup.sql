-- =============================================================================
-- Cortex Agent Cost Observability Lab: Setup Script
-- =============================================================================
-- Run this script as ACCOUNTADMIN (or a role with CREATE DATABASE privileges)
-- before starting the lab notebook.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Lab infrastructure
CREATE DATABASE IF NOT EXISTS AGENT_COST_LAB;
CREATE WAREHOUSE IF NOT EXISTS AGENT_COST_LAB_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
CREATE SCHEMA IF NOT EXISTS AGENT_COST_LAB.PUBLIC;

USE DATABASE AGENT_COST_LAB;
USE SCHEMA PUBLIC;
USE WAREHOUSE AGENT_COST_LAB_WH;

-- =============================================================================
-- Simulated fallback data (for accounts without live Cortex Agent traffic)
-- =============================================================================

CREATE OR REPLACE TABLE SIMULATED_AGENT_USAGE (
    START_TIME TIMESTAMP_LTZ,
    END_TIME TIMESTAMP_LTZ,
    USER_NAME VARCHAR,
    REQUEST_ID VARCHAR,
    AGENT_NAME VARCHAR,
    TOKENS NUMBER,
    TOKEN_CREDITS NUMBER(10,6),
    SERVICE_TYPE VARCHAR,
    MODEL_NAME VARCHAR,
    INPUT_TOKENS NUMBER,
    OUTPUT_TOKENS NUMBER,
    CACHE_READ_INPUT_TOKENS NUMBER,
    CACHE_WRITE_INPUT_TOKENS NUMBER,
    AI_FUNCTIONS_CREDITS NUMBER(10,6)
);

INSERT INTO SIMULATED_AGENT_USAGE VALUES
    ('2026-07-01 09:00:00'::TIMESTAMP_LTZ, '2026-07-01 09:00:04'::TIMESTAMP_LTZ, 'ALICE', 'req-001', 'FINANCE_AGENT', 2400, 0.048000, 'cortex_agents', 'claude-4-sonnet', 1800, 600, 200, 0, NULL),
    ('2026-07-01 09:00:04'::TIMESTAMP_LTZ, '2026-07-01 09:00:06'::TIMESTAMP_LTZ, 'ALICE', 'req-001', 'FINANCE_AGENT', 1100, 0.022000, 'cortex_analyst', 'claude-4-sonnet', 900, 200, 100, 0, 0.005),
    ('2026-07-01 09:15:00'::TIMESTAMP_LTZ, '2026-07-01 09:15:05'::TIMESTAMP_LTZ, 'BOB', 'req-002', 'FINANCE_AGENT', 3200, 0.064000, 'cortex_agents', 'claude-4-sonnet', 2500, 700, 500, 0, NULL),
    ('2026-07-01 09:15:05'::TIMESTAMP_LTZ, '2026-07-01 09:15:07'::TIMESTAMP_LTZ, 'BOB', 'req-002', 'FINANCE_AGENT', 900, 0.018000, 'cortex_analyst', 'claude-4-sonnet', 700, 200, 150, 0, 0.003),
    ('2026-07-01 10:00:00'::TIMESTAMP_LTZ, '2026-07-01 10:00:03'::TIMESTAMP_LTZ, 'ALICE', 'req-003', 'HR_AGENT', 1800, 0.036000, 'cortex_agents', 'llama-4-maverick', 1200, 600, 0, 0, NULL),
    ('2026-07-01 10:30:00'::TIMESTAMP_LTZ, '2026-07-01 10:30:06'::TIMESTAMP_LTZ, 'CAROL', 'req-004', 'FINANCE_AGENT', 4100, 0.082000, 'cortex_agents', 'claude-4-sonnet', 3000, 1100, 800, 0, NULL),
    ('2026-07-01 10:30:06'::TIMESTAMP_LTZ, '2026-07-01 10:30:09'::TIMESTAMP_LTZ, 'CAROL', 'req-004', 'FINANCE_AGENT', 1500, 0.030000, 'cortex_analyst', 'claude-4-sonnet', 1200, 300, 200, 0, 0.008),
    ('2026-07-01 11:00:00'::TIMESTAMP_LTZ, '2026-07-01 11:00:04'::TIMESTAMP_LTZ, 'BOB', 'req-005', 'HR_AGENT', 2000, 0.040000, 'cortex_agents', 'llama-4-maverick', 1500, 500, 100, 0, NULL),
    ('2026-07-01 11:30:00'::TIMESTAMP_LTZ, '2026-07-01 11:30:05'::TIMESTAMP_LTZ, 'DAVE', 'req-006', 'FINANCE_AGENT', 3500, 0.070000, 'cortex_agents', 'claude-4-sonnet', 2600, 900, 600, 0, NULL),
    ('2026-07-01 11:30:05'::TIMESTAMP_LTZ, '2026-07-01 11:30:08'::TIMESTAMP_LTZ, 'DAVE', 'req-006', 'FINANCE_AGENT', 1300, 0.026000, 'cortex_analyst', 'claude-4-sonnet', 1000, 300, 250, 0, 0.006),
    ('2026-07-01 12:00:00'::TIMESTAMP_LTZ, '2026-07-01 12:00:03'::TIMESTAMP_LTZ, 'ALICE', 'req-007', 'FINANCE_AGENT', 2800, 0.056000, 'cortex_agents', 'claude-4-sonnet', 2100, 700, 400, 0, NULL),
    ('2026-07-01 12:00:03'::TIMESTAMP_LTZ, '2026-07-01 12:00:05'::TIMESTAMP_LTZ, 'ALICE', 'req-007', 'FINANCE_AGENT', 1000, 0.020000, 'cortex_analyst', 'claude-4-sonnet', 800, 200, 100, 0, 0.004),
    ('2026-07-01 13:00:00'::TIMESTAMP_LTZ, '2026-07-01 13:00:04'::TIMESTAMP_LTZ, 'CAROL', 'req-008', 'HR_AGENT', 2200, 0.044000, 'cortex_agents', 'llama-4-maverick', 1600, 600, 0, 0, NULL),
    ('2026-07-01 14:00:00'::TIMESTAMP_LTZ, '2026-07-01 14:00:05'::TIMESTAMP_LTZ, 'BOB', 'req-009', 'FINANCE_AGENT', 3000, 0.060000, 'cortex_agents', 'claude-4-sonnet', 2200, 800, 450, 0, NULL),
    ('2026-07-01 14:00:05'::TIMESTAMP_LTZ, '2026-07-01 14:00:07'::TIMESTAMP_LTZ, 'BOB', 'req-009', 'FINANCE_AGENT', 1200, 0.024000, 'cortex_analyst', 'claude-4-sonnet', 950, 250, 180, 0, 0.005),
    ('2026-07-01 15:00:00'::TIMESTAMP_LTZ, '2026-07-01 15:00:04'::TIMESTAMP_LTZ, 'DAVE', 'req-010', 'HR_AGENT', 1900, 0.038000, 'cortex_agents', 'llama-4-maverick', 1400, 500, 50, 0, NULL),
    ('2026-07-02 09:00:00'::TIMESTAMP_LTZ, '2026-07-02 09:00:05'::TIMESTAMP_LTZ, 'ALICE', 'req-011', 'FINANCE_AGENT', 3600, 0.072000, 'cortex_agents', 'claude-4-sonnet', 2800, 800, 700, 0, NULL),
    ('2026-07-02 09:00:05'::TIMESTAMP_LTZ, '2026-07-02 09:00:07'::TIMESTAMP_LTZ, 'ALICE', 'req-011', 'FINANCE_AGENT', 1400, 0.028000, 'cortex_analyst', 'claude-4-sonnet', 1100, 300, 200, 0, 0.007),
    ('2026-07-02 10:00:00'::TIMESTAMP_LTZ, '2026-07-02 10:00:03'::TIMESTAMP_LTZ, 'CAROL', 'req-012', 'FINANCE_AGENT', 2600, 0.052000, 'cortex_agents', 'claude-4-sonnet', 1900, 700, 350, 0, NULL),
    ('2026-07-02 11:00:00'::TIMESTAMP_LTZ, '2026-07-02 11:00:04'::TIMESTAMP_LTZ, 'BOB', 'req-013', 'HR_AGENT', 2100, 0.042000, 'cortex_agents', 'llama-4-maverick', 1500, 600, 0, 0, NULL);

-- Simulated Cortex Analyst hourly rollup
CREATE OR REPLACE TABLE SIMULATED_ANALYST_USAGE (
    START_TIME TIMESTAMP_LTZ,
    END_TIME TIMESTAMP_LTZ,
    REQUEST_COUNT NUMBER,
    CREDITS NUMBER(10,6),
    USERNAME VARCHAR
);

INSERT INTO SIMULATED_ANALYST_USAGE VALUES
    ('2026-07-01 09:00:00'::TIMESTAMP_LTZ, '2026-07-01 10:00:00'::TIMESTAMP_LTZ, 2, 0.040000, 'ALICE'),
    ('2026-07-01 09:00:00'::TIMESTAMP_LTZ, '2026-07-01 10:00:00'::TIMESTAMP_LTZ, 1, 0.018000, 'BOB'),
    ('2026-07-01 10:00:00'::TIMESTAMP_LTZ, '2026-07-01 11:00:00'::TIMESTAMP_LTZ, 1, 0.030000, 'CAROL'),
    ('2026-07-01 11:00:00'::TIMESTAMP_LTZ, '2026-07-01 12:00:00'::TIMESTAMP_LTZ, 1, 0.026000, 'DAVE'),
    ('2026-07-01 12:00:00'::TIMESTAMP_LTZ, '2026-07-01 13:00:00'::TIMESTAMP_LTZ, 1, 0.020000, 'ALICE'),
    ('2026-07-01 14:00:00'::TIMESTAMP_LTZ, '2026-07-01 15:00:00'::TIMESTAMP_LTZ, 1, 0.024000, 'BOB'),
    ('2026-07-02 09:00:00'::TIMESTAMP_LTZ, '2026-07-02 10:00:00'::TIMESTAMP_LTZ, 1, 0.028000, 'ALICE');

-- Simulated warehouse compute attribution
CREATE OR REPLACE TABLE SIMULATED_QUERY_ATTRIBUTION (
    QUERY_ID VARCHAR,
    USER_NAME VARCHAR,
    WAREHOUSE_NAME VARCHAR,
    QUERY_TAG VARCHAR,
    START_TIME TIMESTAMP_LTZ,
    CREDITS_ATTRIBUTED_COMPUTE FLOAT
);

INSERT INTO SIMULATED_QUERY_ATTRIBUTION VALUES
    ('req-001', 'ALICE', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 09:00:05'::TIMESTAMP_LTZ, 0.000120),
    ('req-002', 'BOB', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 09:15:07'::TIMESTAMP_LTZ, 0.000180),
    ('req-004', 'CAROL', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 10:30:09'::TIMESTAMP_LTZ, 0.000210),
    ('req-006', 'DAVE', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 11:30:08'::TIMESTAMP_LTZ, 0.000150),
    ('req-007', 'ALICE', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 12:00:05'::TIMESTAMP_LTZ, 0.000090),
    ('req-009', 'BOB', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-01 14:00:07'::TIMESTAMP_LTZ, 0.000160),
    ('req-011', 'ALICE', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-02 09:00:07'::TIMESTAMP_LTZ, 0.000200),
    ('req-012', 'CAROL', 'AGENT_COST_LAB_WH', 'app=finance_agent', '2026-07-02 10:00:04'::TIMESTAMP_LTZ, 0.000140);

SELECT 'Setup complete. Lab objects created in AGENT_COST_LAB database.' AS STATUS;
