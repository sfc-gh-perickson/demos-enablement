-- =============================================================================
-- Cortex AI Gateway + LangChain + MCP: Setup Script
-- =============================================================================
-- Run this script before starting the notebook.
-- Creates: database, tables, semantic view, Cortex Search service,
--          and AI Gateway route configuration.
--
-- Prerequisites:
--   - ACCOUNTADMIN or a role with CREATE DATABASE, CREATE WAREHOUSE
--   - Cross-region inference enabled (ALTER ACCOUNT SET
--     CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION') for broader model access.
--     Model availability through the gateway varies by region AND over time even
--     with cross-region enabled: a 503 means the gateway could not serve that
--     model at that moment, which is often transient capacity rather than a
--     misconfiguration. Confirm with a test request before building a demo
--     around a specific model, and keep a fallback in mind.
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS CORTEX_GATEWAY_LAB;
USE DATABASE CORTEX_GATEWAY_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS GATEWAY_LAB_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE GATEWAY_LAB_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. CAMPAIGN SPEND TABLE (structured data for SQL queries via MCP)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE CAMPAIGN_SPEND (
    CHANNEL         VARCHAR,
    MONTH           DATE,
    CAMPAIGN_NAME   VARCHAR,
    SPEND           NUMBER(12,2),
    IMPRESSIONS     NUMBER,
    CLICKS          NUMBER,
    CONVERSIONS     NUMBER,
    REVENUE         NUMBER(12,2)
);

INSERT INTO CAMPAIGN_SPEND VALUES
-- Paid Search
('Paid Search', '2024-01-01', 'Q1 Brand Awareness',      45000.00,  520000,  15600,  780, 156000.00),
('Paid Search', '2024-02-01', 'Q1 Brand Awareness',      48000.00,  545000,  16350,  818, 163500.00),
('Paid Search', '2024-03-01', 'Q1 Brand Awareness',      52000.00,  580000,  17400,  870, 174000.00),
('Paid Search', '2024-04-01', 'Q2 Product Launch',       62000.00,  650000,  19500,  975, 214500.00),
('Paid Search', '2024-05-01', 'Q2 Product Launch',       58000.00,  610000,  18300,  915, 201300.00),
('Paid Search', '2024-06-01', 'Q2 Product Launch',       55000.00,  590000,  17700,  885, 185850.00),
('Paid Search', '2024-07-01', 'H2 Performance Max',      50000.00,  560000,  16800,  840, 176400.00),
('Paid Search', '2024-08-01', 'H2 Performance Max',      53000.00,  575000,  17250,  863, 181125.00),
('Paid Search', '2024-09-01', 'H2 Performance Max',      56000.00,  600000,  18000,  900, 189000.00),
('Paid Search', '2024-10-01', 'Q4 Holiday Push',         72000.00,  780000,  23400, 1170, 280800.00),
('Paid Search', '2024-11-01', 'Q4 Holiday Push',         85000.00,  920000,  27600, 1380, 345000.00),
('Paid Search', '2024-12-01', 'Q4 Holiday Push',         90000.00,  980000,  29400, 1470, 367500.00),

-- Social Media
('Social Media', '2024-01-01', 'Q1 Brand Awareness',     32000.00,  890000,   8900,  356, 62300.00),
('Social Media', '2024-02-01', 'Q1 Brand Awareness',     34000.00,  920000,   9200,  368, 64400.00),
('Social Media', '2024-03-01', 'Q1 Brand Awareness',     36000.00,  960000,   9600,  384, 67200.00),
('Social Media', '2024-04-01', 'Q2 Influencer Program',  42000.00, 1100000,  11000,  440, 88000.00),
('Social Media', '2024-05-01', 'Q2 Influencer Program',  44000.00, 1150000,  11500,  460, 92000.00),
('Social Media', '2024-06-01', 'Q2 Influencer Program',  40000.00, 1050000,  10500,  420, 84000.00),
('Social Media', '2024-07-01', 'H2 Community Growth',    38000.00, 1000000,  10000,  400, 76000.00),
('Social Media', '2024-08-01', 'H2 Community Growth',    39000.00, 1020000,  10200,  408, 77520.00),
('Social Media', '2024-09-01', 'H2 Community Growth',    41000.00, 1080000,  10800,  432, 82080.00),
('Social Media', '2024-10-01', 'Q4 Holiday Push',        55000.00, 1400000,  14000,  560, 112000.00),
('Social Media', '2024-11-01', 'Q4 Holiday Push',        62000.00, 1580000,  15800,  632, 126400.00),
('Social Media', '2024-12-01', 'Q4 Holiday Push',        58000.00, 1500000,  15000,  600, 120000.00),

-- Email
('Email', '2024-01-01', 'Q1 Brand Awareness',            8000.00,  180000,  14400, 1008, 90720.00),
('Email', '2024-02-01', 'Q1 Brand Awareness',            8500.00,  190000,  15200, 1064, 95760.00),
('Email', '2024-03-01', 'Q1 Brand Awareness',            9000.00,  200000,  16000, 1120, 100800.00),
('Email', '2024-04-01', 'Q2 Nurture Sequences',         10000.00,  220000,  17600, 1232, 123200.00),
('Email', '2024-05-01', 'Q2 Nurture Sequences',         10500.00,  230000,  18400, 1288, 128800.00),
('Email', '2024-06-01', 'Q2 Nurture Sequences',         11000.00,  240000,  19200, 1344, 134400.00),
('Email', '2024-07-01', 'H2 Retention Series',           9500.00,  210000,  16800, 1176, 105840.00),
('Email', '2024-08-01', 'H2 Retention Series',           9800.00,  215000,  17200, 1204, 108360.00),
('Email', '2024-09-01', 'H2 Retention Series',          10200.00,  225000,  18000, 1260, 113400.00),
('Email', '2024-10-01', 'Q4 Holiday Push',              14000.00,  310000,  24800, 1736, 173600.00),
('Email', '2024-11-01', 'Q4 Holiday Push',              16000.00,  350000,  28000, 1960, 196000.00),
('Email', '2024-12-01', 'Q4 Holiday Push',              15000.00,  330000,  26400, 1848, 184800.00),

-- Display
('Display', '2024-01-01', 'Q1 Brand Awareness',         22000.00, 1200000,   6000,  180, 27000.00),
('Display', '2024-02-01', 'Q1 Brand Awareness',         23000.00, 1250000,   6250,  188, 28125.00),
('Display', '2024-03-01', 'Q1 Brand Awareness',         24000.00, 1300000,   6500,  195, 29250.00),
('Display', '2024-04-01', 'Q2 Retargeting',             28000.00, 1500000,   7500,  225, 38250.00),
('Display', '2024-05-01', 'Q2 Retargeting',             30000.00, 1600000,   8000,  240, 40800.00),
('Display', '2024-06-01', 'Q2 Retargeting',             27000.00, 1450000,   7250,  218, 37005.00),
('Display', '2024-07-01', 'H2 Programmatic',            25000.00, 1350000,   6750,  203, 32437.50),
('Display', '2024-08-01', 'H2 Programmatic',            26000.00, 1400000,   7000,  210, 33600.00),
('Display', '2024-09-01', 'H2 Programmatic',            27000.00, 1450000,   7250,  218, 34875.00),
('Display', '2024-10-01', 'Q4 Holiday Push',            35000.00, 1850000,   9250,  278, 47175.00),
('Display', '2024-11-01', 'Q4 Holiday Push',            40000.00, 2100000,  10500,  315, 53550.00),
('Display', '2024-12-01', 'Q4 Holiday Push',            38000.00, 2000000,  10000,  300, 51000.00);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. STRATEGY DOCUMENTS TABLE (unstructured data for Cortex Search via MCP)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE STRATEGY_DOCS (
    DOC_ID      VARCHAR,
    TITLE       VARCHAR,
    CONTENT     VARCHAR,
    DOC_TYPE    VARCHAR
);

INSERT INTO STRATEGY_DOCS VALUES
('DOC-001', 'Channel Strategy 2024',
 'Our 2024 channel strategy focuses on a balanced portfolio approach across four primary channels: Paid Search, Social Media, Email, and Display. Paid Search remains our highest-performing channel for direct response and should receive 40% of total budget. Social Media is our primary brand awareness and community-building channel, allocated 25% of budget. Email remains the most cost-efficient channel with the highest conversion rates and receives 10% of budget. Display advertising supports retargeting and top-of-funnel awareness at 15% of budget. The remaining 10% is held as a flex budget for opportunistic campaigns and testing.',
 'strategy'),

('DOC-002', 'Attribution Methodology',
 'We use a data-driven multi-touch attribution model that assigns credit to marketing touchpoints based on their actual contribution to conversions. The model uses a 30-day lookback window and applies diminishing returns to touchpoints further from conversion. First-touch receives a base weight of 0.2, last-touch receives 0.3, and middle touches share the remaining 0.5 proportional to their recency and engagement depth. Revenue attribution is calculated at the channel level by aggregating individual conversion paths. We report on both attributed revenue (model-based) and last-click revenue for comparison. All attribution data refreshes daily with a 48-hour lag for conversion window completion.',
 'methodology'),

('DOC-003', 'Q4 Planning Brief',
 'Q4 2024 represents our peak revenue period with an expected 35% lift over Q3 baseline. Key initiatives include: (1) Holiday Push campaign across all channels starting October 1, (2) aggressive paid search bidding on Black Friday and Cyber Monday with 2x daily budgets, (3) email frequency increase to 3x per week during November-December, (4) social media influencer partnerships for holiday gift guides. Total Q4 budget is $590,000, a 45% increase over Q3. Success metrics: achieve ROAS of 3.5x or higher across the portfolio, maintain CPA below $45, and drive 15,000+ conversions across Q4.',
 'brief'),

('DOC-004', 'Budget Allocation Methodology',
 'Budget allocation follows a performance-based model updated quarterly. We use three inputs to determine channel budgets: (1) Historical ROI by channel over the trailing 6 months, (2) Market opportunity size estimated via impression share and competitive intelligence, (3) Strategic priorities set by leadership for the planning period. Channels that exceed their ROI target by more than 20% receive automatic budget increases of up to 15% in the next period. Channels that underperform their ROI target by more than 20% for two consecutive periods trigger a review and potential reallocation. Minimum viable spend is maintained for all channels to preserve learnings and audience data.',
 'methodology'),

('DOC-005', 'Brand Guidelines for Reporting',
 'All marketing performance reports must adhere to the following standards: (1) Currency should be reported in USD, rounded to 2 decimal places. (2) Percentages should be displayed to 1 decimal place. (3) When reporting ROI, use the formula: (Revenue - Spend) / Spend, expressed as a ratio (e.g., 3.2x not 320%). (4) Time periods must be explicitly stated in all data presentations. (5) Channel names must use official nomenclature: Paid Search, Social Media, Email, Display. (6) Year-over-year comparisons should note any methodology changes. (7) Executive summaries must lead with the single most impactful insight, followed by supporting data.',
 'guidelines'),

('DOC-006', 'Performance Benchmarks 2024',
 'Internal benchmarks for 2024 marketing performance by channel. Paid Search: target CPC $3.00-$3.50, target conversion rate 5.0%, target ROAS 3.0x. Social Media: target CPC $3.50-$4.50, target conversion rate 4.0%, target ROAS 1.8x. Email: target open rate 8.0%, target conversion rate 7.0%, target ROAS 10.0x. Display: target CPM $18-$22, target conversion rate 3.0%, target ROAS 1.2x. These benchmarks are reviewed quarterly and adjusted based on market conditions and seasonal factors. Channels exceeding benchmarks by 20%+ are flagged for increased investment.',
 'methodology');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEW (for Cortex Analyst queries via MCP)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SEMANTIC VIEW CMO_ANALYTICS
  tables (
    CORTEX_GATEWAY_LAB.PUBLIC.CAMPAIGN_SPEND
  )
  dimensions (
    CAMPAIGN_SPEND.CAMPAIGN_NAME as CAMPAIGN_NAME comment='Named marketing campaign',
    CAMPAIGN_SPEND.CHANNEL as CHANNEL comment='Marketing channel: Paid Search, Social Media, Email, or Display',
    CAMPAIGN_SPEND.MONTH as MONTH comment='Calendar month of the campaign spend'
  )
  metrics (
    CAMPAIGN_SPEND.TOTAL_SPEND as SUM(SPEND) comment='Total marketing spend in USD',
    CAMPAIGN_SPEND.TOTAL_REVENUE as SUM(REVENUE) comment='Total attributed revenue in USD',
    CAMPAIGN_SPEND.TOTAL_IMPRESSIONS as SUM(IMPRESSIONS) comment='Total ad impressions served',
    CAMPAIGN_SPEND.TOTAL_CLICKS as SUM(CLICKS) comment='Total clicks on ads',
    CAMPAIGN_SPEND.TOTAL_CONVERSIONS as SUM(CONVERSIONS) comment='Total conversions attributed to marketing',
    CAMPAIGN_SPEND.ROI as (SUM(REVENUE) - SUM(SPEND)) / NULLIF(SUM(SPEND), 0) comment='Return on investment as a multiplier (e.g., 3.2x)',
    CAMPAIGN_SPEND.CPC as SUM(SPEND) / NULLIF(SUM(CLICKS), 0) comment='Cost per click in USD',
    CAMPAIGN_SPEND.CPA as SUM(SPEND) / NULLIF(SUM(CONVERSIONS), 0) comment='Cost per acquisition in USD',
    CAMPAIGN_SPEND.ROAS as SUM(REVENUE) / NULLIF(SUM(SPEND), 0) comment='Return on ad spend: revenue divided by spend'
  )
  comment='Marketing campaign performance analytics'
  ai_sql_generation 'If no date filter is specified, default to the full year 2024. Round currency to 2 decimal places. Express ROI as a multiplier (e.g., 2.5x). Use official channel names: Paid Search, Social Media, Email, Display.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX SEARCH SERVICE (for RAG over strategy docs via MCP)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE CORTEX SEARCH SERVICE STRATEGY_SEARCH_SVC
  ON CONTENT
  ATTRIBUTES DOC_TYPE
  WAREHOUSE = GATEWAY_LAB_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT
    DOC_ID,
    TITLE,
    CONTENT,
    DOC_TYPE
  FROM STRATEGY_DOCS
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. MCP SERVER (exposes Analyst + Search as tools for external LLM agents)
-- ─────────────────────────────────────────────────────────────────────────────
-- The MCP server is a standalone object — no Cortex Agent required.
-- Clients connect via streamable HTTP at:
--   POST /api/v2/databases/CORTEX_GATEWAY_LAB/schemas/PUBLIC/mcp-servers/MARKETING_MCP

CREATE OR REPLACE MCP SERVER MARKETING_MCP FROM SPECIFICATION $$
tools:
  - name: query_campaigns
    description: "Query marketing campaign performance data (spend, revenue, ROI, conversions) using natural language. Returns a SQL query and interpretation. Use execute_sql to run the returned query and get actual data."
    type: "CORTEX_ANALYST_MESSAGE"
    identifier: "CORTEX_GATEWAY_LAB.PUBLIC.CMO_ANALYTICS"

  - name: search_strategy_docs
    description: "Search marketing strategy documents, methodologies, planning briefs, and guidelines."
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    identifier: "CORTEX_GATEWAY_LAB.PUBLIC.STRATEGY_SEARCH_SVC"

  - name: execute_sql
    description: "Execute a SQL query against Snowflake and return the result rows. Use this to run SQL generated by query_campaigns."
    type: "SYSTEM_EXECUTE_SQL"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. GRANTS (required if your PAT is role-restricted)
-- ─────────────────────────────────────────────────────────────────────────────
-- A PAT created with ROLE_RESTRICTION acts as that role only. Without these
-- grants the MCP server returns:
--   "MCP server ... does not exist or not authorized"
-- even though the object exists and SHOW MCP SERVERS lists it as the owner.
--
-- Set LAB_ROLE to the role your PAT is restricted to, then run this section.
-- If your PAT is unrestricted and inherits ACCOUNTADMIN, you can skip it.

SET LAB_ROLE = 'AI_GATEWAY_USER';
SET LAB_USER = CURRENT_USER();

CREATE ROLE IF NOT EXISTS IDENTIFIER($LAB_ROLE);
GRANT ROLE IDENTIFIER($LAB_ROLE) TO USER IDENTIFIER($LAB_USER);

GRANT USAGE ON WAREHOUSE GATEWAY_LAB_WH            TO ROLE IDENTIFIER($LAB_ROLE);
GRANT USAGE ON DATABASE CORTEX_GATEWAY_LAB         TO ROLE IDENTIFIER($LAB_ROLE);
GRANT USAGE ON SCHEMA CORTEX_GATEWAY_LAB.PUBLIC    TO ROLE IDENTIFIER($LAB_ROLE);
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC
                                                   TO ROLE IDENTIFIER($LAB_ROLE);
GRANT SELECT ON SEMANTIC VIEW CORTEX_GATEWAY_LAB.PUBLIC.CMO_ANALYTICS
                                                   TO ROLE IDENTIFIER($LAB_ROLE);
GRANT USAGE ON CORTEX SEARCH SERVICE CORTEX_GATEWAY_LAB.PUBLIC.STRATEGY_SEARCH_SVC
                                                   TO ROLE IDENTIFIER($LAB_ROLE);
GRANT USAGE ON MCP SERVER CORTEX_GATEWAY_LAB.PUBLIC.MARKETING_MCP
                                                   TO ROLE IDENTIFIER($LAB_ROLE);
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER          TO ROLE IDENTIFIER($LAB_ROLE);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. AI GATEWAY CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────
-- The AI Gateway is auto-provisioned per account (named SNOWFLAKE).
--
-- URL paths. Read the authoritative inference base_url off SHOW AI GATEWAYS
-- rather than hardcoding it:
--   Inference: /api/v2/aigateways/snowflake/v1/chat/completions  (OpenAI-compatible)
--              /api/v2/aigateways/snowflake/v1/messages          (Anthropic-compatible)
--   Admin:     /api/v2/aigateways/SNOWFLAKE                      (spec management)
--
-- Do NOT use /api/v2/cortex/v1/*. That is the separate Cortex Inference REST
-- API. It also answers, so a wrong base_url fails silently rather than
-- erroring -- but it bypasses the gateway entirely, so those calls never reach
-- AI_GATEWAY_USAGE_HISTORY, never appear in gateway traces, and are not subject
-- to the model allowlist, budgets, or quotas configured below.
--
-- Note: the base_url returned by SHOW AI GATEWAYS contains the account name
-- verbatim, which may include underscores. Replace underscores with hyphens
-- before making requests or TLS verification fails.

-- The gateway is ACCOUNT-LEVEL and SHARED. Capture the current spec first so
-- you can restore it during cleanup -- the ALTER below replaces it wholesale.
SHOW AI GATEWAYS;

-- The spec defines:
--   models:   allowlist of model name patterns (* = all models)
--   logging:  trace capture, client telemetry, payload recording
--
-- WARNING: capture_payload.request_response records full prompt and completion
-- text for EVERY caller on this account, not just this lab. Leave it off on any
-- account with real workloads or sensitive data.

ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
models:
  - name: '*'
logging:
  enabled: true
  enable_client_telemetry: true
  capture_payload:
    request_response: true
$$;

-- Verify the gateway configuration
SHOW AI GATEWAYS;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. VERIFY SETUP
-- ─────────────────────────────────────────────────────────────────────────────

SHOW TABLES IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC;
SHOW CORTEX SEARCH SERVICES IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC;
SHOW MCP SERVERS IN SCHEMA CORTEX_GATEWAY_LAB.PUBLIC;
