-- =============================================================================
-- Scoping Agentic Implementations: Lab Setup
-- =============================================================================
-- This script creates the lab environment for the scoping workshop.
-- It includes: database/schema, a mock observability table with realistic
-- usage data, and a stub agent to demonstrate the spec-to-implementation flow.
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
-- Mock Observability Data
-- =============================================================================
-- This table simulates CORTEX_AGENT_USAGE_HISTORY for the workshop.
-- It shows realistic usage patterns with intentional gaps between
-- expected taxonomy and actual usage to drive the iteration exercise.

CREATE OR REPLACE TABLE MOCK_AGENT_USAGE (
    INTERACTION_ID VARCHAR,
    TIMESTAMP TIMESTAMP_NTZ,
    USER_QUESTION VARCHAR,
    QUESTION_CATEGORY VARCHAR,
    USER_ROLE VARCHAR,
    SURFACE VARCHAR,
    TOKENS_USED NUMBER,
    LATENCY_MS NUMBER,
    TOOL_CALLS VARIANT
);

-- Insert mock data with realistic distribution that DIFFERS from expected taxonomy
-- Expected: 50% lookup, 25% aggregation, 10% reasoning, 10% policy, 5% out_of_scope
-- Actual: shows more aggregation, surprise reasoning, and unexpected personas

INSERT INTO MOCK_AGENT_USAGE VALUES
-- Lookup questions (35% actual vs 50% expected — lower than anticipated)
('int_001', '2024-11-01 09:15:00', 'What was Q3 revenue for the West region?', 'LOOKUP', 'Sales Manager', 'snowsight', 1200, 2300, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_002', '2024-11-01 09:22:00', 'How many deals closed in October?', 'LOOKUP', 'Sales Manager', 'snowsight', 980, 1800, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_003', '2024-11-01 10:05:00', 'Who is our top customer by ARR?', 'LOOKUP', 'Sales Manager', 'external', 1100, 2100, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_004', '2024-11-01 11:30:00', 'What is the average deal size this quarter?', 'LOOKUP', 'Sales Rep', 'snowsight', 1050, 1950, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_005', '2024-11-01 14:00:00', 'How many opportunities are in Stage 3?', 'LOOKUP', 'Sales Manager', 'external', 900, 1600, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_006', '2024-11-02 08:45:00', 'What was last month total pipeline value?', 'LOOKUP', 'Sales Manager', 'snowsight', 1150, 2200, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_007', '2024-11-02 10:10:00', 'How many new customers did we add in Q3?', 'LOOKUP', 'Sales Manager', 'snowsight', 1300, 2500, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),

-- Aggregation questions (30% actual vs 25% expected — higher than expected)
('int_008', '2024-11-01 09:45:00', 'Compare YoY growth by product line', 'AGGREGATION', 'Sales Manager', 'snowsight', 2800, 4500, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_009', '2024-11-01 10:30:00', 'Which region has the best conversion rate?', 'AGGREGATION', 'VP Sales', 'snowsight', 2400, 3800, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_010', '2024-11-01 13:15:00', 'Show me win rates by deal size bucket', 'AGGREGATION', 'Sales Manager', 'external', 3200, 5200, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_011', '2024-11-01 15:00:00', 'What is the trend in average sales cycle over the last 4 quarters?', 'AGGREGATION', 'VP Sales', 'snowsight', 3500, 5800, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_012', '2024-11-02 09:00:00', 'Compare pipeline velocity across regions', 'AGGREGATION', 'Sales Manager', 'snowsight', 2900, 4600, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),
('int_013', '2024-11-02 11:20:00', 'Show month-over-month revenue growth for enterprise segment', 'AGGREGATION', 'Finance Analyst', 'snowsight', 2600, 4200, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}]')),

-- Reasoning questions (15% actual vs 10% expected — users ask harder questions than anticipated)
('int_014', '2024-11-01 11:00:00', 'Why did the Northeast region underperform last quarter?', 'REASONING', 'VP Sales', 'snowsight', 6500, 12000, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}, {"tool": "cortex_search", "success": false}]')),
('int_015', '2024-11-01 14:30:00', 'What factors are driving the increase in deal cycle time?', 'REASONING', 'Sales Manager', 'snowsight', 7200, 14000, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}, {"tool": "cortex_search", "success": true}]')),
('int_016', '2024-11-02 10:45:00', 'Why are we losing more deals to Competitor X this quarter vs last?', 'REASONING', 'VP Sales', 'external', 8100, 16000, PARSE_JSON('[{"tool": "cortex_analyst", "success": true}, {"tool": "cortex_search", "success": false}]')),

-- Policy questions (5% actual vs 10% expected — fewer than anticipated)
('int_017', '2024-11-01 16:00:00', 'What is our discount approval threshold for enterprise?', 'POLICY', 'Sales Rep', 'snowsight', 1800, 3200, PARSE_JSON('[{"tool": "cortex_search", "success": true}]')),

-- Out of scope (15% actual vs 5% expected — much higher than anticipated)
('int_018', '2024-11-01 12:00:00', 'Draft a follow-up email for the Acme meeting', 'OUT_OF_SCOPE', 'Sales Rep', 'external', 500, 800, PARSE_JSON('[]')),
('int_019', '2024-11-01 13:45:00', 'What should my pricing proposal look like?', 'OUT_OF_SCOPE', 'Sales Rep', 'snowsight', 600, 900, PARSE_JSON('[]')),
('int_020', '2024-11-02 14:00:00', 'Can you update the CRM with this deal info?', 'OUT_OF_SCOPE', 'Sales Rep', 'external', 450, 700, PARSE_JSON('[]'));


-- =============================================================================
-- Stub Agent Definition
-- =============================================================================
-- This demonstrates the spec-to-implementation flow. In production, you'd
-- create the full agent after completing the scoping exercise.

-- Note: Uncomment and adjust if your account has agent creation enabled.
-- The agent below matches the spec template from the workshop.

/*
CREATE OR REPLACE CORTEX AGENT SCOPING_LAB.PUBLIC.SALES_INSIGHTS_AGENT
  COMMENT = 'Phase 1: Sales lookup and aggregation for Regional Sales Managers'
  MODEL = 'claude-sonnet'
  TOOLS = (
    -- Phase 1: Semantic View for structured data queries
    -- SEMANTIC_VIEW = 'SCOPING_LAB.PUBLIC.SALES_SEMANTIC_VIEW'
  )
  INSTRUCTIONS = $$
You are a sales insights assistant for Regional Sales Managers.

CAPABILITIES:
- Answer questions about revenue, pipeline, deals, and customers
- Provide comparisons across regions, time periods, and product lines
- Calculate metrics like win rate, conversion rate, and deal velocity

BOUNDARIES:
- Do NOT generate content (emails, proposals, presentations)
- Do NOT provide competitor information
- Do NOT modify data or take actions in external systems
- If asked about something outside your scope, politely explain your boundaries

RESPONSE FORMAT:
- Lead with the direct answer to the question
- Include relevant context (time period, filters applied)
- Note any caveats or data limitations
$$;
*/


-- =============================================================================
-- Semantic View Stub (Phase 1 prerequisite)
-- =============================================================================
-- This shows the structure a semantic view would need for Phase 1.
-- In production, you'd build this over your actual sales tables.

CREATE OR REPLACE TABLE SAMPLE_SALES_DATA (
    DEAL_ID VARCHAR,
    REGION VARCHAR,
    PRODUCT_LINE VARCHAR,
    REVENUE NUMBER(12,2),
    CLOSE_DATE DATE,
    STAGE VARCHAR,
    CUSTOMER_NAME VARCHAR,
    DEAL_SIZE_BUCKET VARCHAR,
    SALES_CYCLE_DAYS NUMBER
);

-- Insert sample data for the semantic view stub
INSERT INTO SAMPLE_SALES_DATA VALUES
('D001', 'West', 'Enterprise', 4200000.00, '2024-06-15', 'Closed Won', 'Acme Corp', 'Large', 45),
('D002', 'East', 'Mid-Market', 850000.00, '2024-06-20', 'Closed Won', 'Beta Inc', 'Medium', 30),
('D003', 'West', 'Enterprise', 3100000.00, '2024-07-10', 'Closed Won', 'Gamma LLC', 'Large', 60),
('D004', 'Northeast', 'SMB', 120000.00, '2024-07-22', 'Closed Lost', 'Delta Co', 'Small', 25),
('D005', 'South', 'Mid-Market', 950000.00, '2024-08-05', 'Closed Won', 'Epsilon Ltd', 'Medium', 35),
('D006', 'West', 'Enterprise', 5500000.00, '2024-08-18', 'Stage 3', 'Zeta Corp', 'Large', NULL),
('D007', 'East', 'SMB', 200000.00, '2024-09-01', 'Closed Won', 'Eta Inc', 'Small', 20),
('D008', 'Northeast', 'Enterprise', 2800000.00, '2024-09-15', 'Closed Lost', 'Theta Group', 'Large', 90),
('D009', 'South', 'Mid-Market', 1100000.00, '2024-10-01', 'Closed Won', 'Iota LLC', 'Medium', 40),
('D010', 'West', 'Enterprise', 6200000.00, '2024-10-20', 'Stage 4', 'Kappa Corp', 'Large', NULL);

-- =============================================================================
-- Setup Complete
-- =============================================================================
-- Lab environment ready. Proceed to the workshop notebook.
--
-- Resources created:
--   Database: SCOPING_LAB
--   Warehouse: SCOPING_LAB_WH (XS, auto-suspend 60s)
--   Tables:
--     - MOCK_AGENT_USAGE (simulated observability data)
--     - SAMPLE_SALES_DATA (semantic view prerequisite stub)
-- =============================================================================
