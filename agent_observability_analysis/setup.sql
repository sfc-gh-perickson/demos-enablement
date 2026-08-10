-- =============================================================================
-- Observability-to-Evaluations Demo: Setup Script
-- =============================================================================
-- This script ensures the CMO_EVAL_LAB environment exists and adds tables
-- specific to the observability mining workflow.
--
-- If you've already run ../evaluations/lab/setup.sql, this script only adds
-- the additional objects needed for this demo.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Cross-region inference enabled (for CORTEX.COMPLETE and AI_EMBED)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - READ UNREDACTED AI OBSERVABILITY EVENTS TABLE privilege (for full feedback text)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE, SCHEMA, WAREHOUSE (idempotent)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS CMO_EVAL_LAB;
USE DATABASE CMO_EVAL_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

CREATE WAREHOUSE IF NOT EXISTS CMO_EVAL_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE CMO_EVAL_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CAMPAIGN SPEND TABLE (if not already created by evaluations/lab/setup.sql)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS CAMPAIGN_SPEND (
    CHANNEL         VARCHAR,
    MONTH           DATE,
    CAMPAIGN_NAME   VARCHAR,
    SPEND           NUMBER(12,2),
    IMPRESSIONS     NUMBER,
    CLICKS          NUMBER,
    CONVERSIONS     NUMBER,
    REVENUE         NUMBER(12,2)
);

-- Only insert if table is empty (idempotent)
INSERT INTO CAMPAIGN_SPEND
SELECT * FROM (
    SELECT 'Paid Search' AS CHANNEL, '2024-01-01'::DATE AS MONTH, 'Q1 Brand Awareness' AS CAMPAIGN_NAME, 45000.00 AS SPEND, 520000 AS IMPRESSIONS, 15600 AS CLICKS, 780 AS CONVERSIONS, 156000.00 AS REVENUE
    UNION ALL SELECT 'Paid Search', '2024-02-01', 'Q1 Brand Awareness', 48000.00, 545000, 16350, 818, 163500.00
    UNION ALL SELECT 'Paid Search', '2024-03-01', 'Q1 Brand Awareness', 52000.00, 580000, 17400, 870, 174000.00
    UNION ALL SELECT 'Paid Search', '2024-04-01', 'Q2 Product Launch', 62000.00, 650000, 19500, 975, 214500.00
    UNION ALL SELECT 'Paid Search', '2024-05-01', 'Q2 Product Launch', 58000.00, 610000, 18300, 915, 201300.00
    UNION ALL SELECT 'Paid Search', '2024-06-01', 'Q2 Product Launch', 55000.00, 590000, 17700, 885, 185850.00
    UNION ALL SELECT 'Paid Search', '2024-07-01', 'H2 Performance Max', 50000.00, 560000, 16800, 840, 176400.00
    UNION ALL SELECT 'Paid Search', '2024-08-01', 'H2 Performance Max', 53000.00, 575000, 17250, 863, 181125.00
    UNION ALL SELECT 'Paid Search', '2024-09-01', 'H2 Performance Max', 56000.00, 600000, 18000, 900, 189000.00
    UNION ALL SELECT 'Paid Search', '2024-10-01', 'Q4 Holiday Push', 72000.00, 780000, 23400, 1170, 280800.00
    UNION ALL SELECT 'Paid Search', '2024-11-01', 'Q4 Holiday Push', 85000.00, 920000, 27600, 1380, 345000.00
    UNION ALL SELECT 'Paid Search', '2024-12-01', 'Q4 Holiday Push', 90000.00, 980000, 29400, 1470, 367500.00
    UNION ALL SELECT 'Social Media', '2024-01-01', 'Q1 Brand Awareness', 32000.00, 890000, 8900, 356, 62300.00
    UNION ALL SELECT 'Social Media', '2024-02-01', 'Q1 Brand Awareness', 34000.00, 920000, 9200, 368, 64400.00
    UNION ALL SELECT 'Social Media', '2024-03-01', 'Q1 Brand Awareness', 36000.00, 960000, 9600, 384, 67200.00
    UNION ALL SELECT 'Social Media', '2024-04-01', 'Q2 Influencer Program', 42000.00, 1100000, 11000, 440, 88000.00
    UNION ALL SELECT 'Social Media', '2024-05-01', 'Q2 Influencer Program', 44000.00, 1150000, 11500, 460, 92000.00
    UNION ALL SELECT 'Social Media', '2024-06-01', 'Q2 Influencer Program', 40000.00, 1050000, 10500, 420, 84000.00
    UNION ALL SELECT 'Social Media', '2024-07-01', 'H2 Community Growth', 38000.00, 1000000, 10000, 400, 76000.00
    UNION ALL SELECT 'Social Media', '2024-08-01', 'H2 Community Growth', 39000.00, 1020000, 10200, 408, 77520.00
    UNION ALL SELECT 'Social Media', '2024-09-01', 'H2 Community Growth', 41000.00, 1080000, 10800, 432, 82080.00
    UNION ALL SELECT 'Social Media', '2024-10-01', 'Q4 Holiday Push', 55000.00, 1400000, 14000, 560, 112000.00
    UNION ALL SELECT 'Social Media', '2024-11-01', 'Q4 Holiday Push', 62000.00, 1580000, 15800, 632, 126400.00
    UNION ALL SELECT 'Social Media', '2024-12-01', 'Q4 Holiday Push', 58000.00, 1500000, 15000, 600, 120000.00
    UNION ALL SELECT 'Email', '2024-01-01', 'Q1 Brand Awareness', 8000.00, 180000, 14400, 1008, 90720.00
    UNION ALL SELECT 'Email', '2024-02-01', 'Q1 Brand Awareness', 8500.00, 190000, 15200, 1064, 95760.00
    UNION ALL SELECT 'Email', '2024-03-01', 'Q1 Brand Awareness', 9000.00, 200000, 16000, 1120, 100800.00
    UNION ALL SELECT 'Email', '2024-04-01', 'Q2 Nurture Sequences', 10000.00, 220000, 17600, 1232, 123200.00
    UNION ALL SELECT 'Email', '2024-05-01', 'Q2 Nurture Sequences', 10500.00, 230000, 18400, 1288, 128800.00
    UNION ALL SELECT 'Email', '2024-06-01', 'Q2 Nurture Sequences', 11000.00, 240000, 19200, 1344, 134400.00
    UNION ALL SELECT 'Email', '2024-07-01', 'H2 Retention Series', 9500.00, 210000, 16800, 1176, 105840.00
    UNION ALL SELECT 'Email', '2024-08-01', 'H2 Retention Series', 9800.00, 215000, 17200, 1204, 108360.00
    UNION ALL SELECT 'Email', '2024-09-01', 'H2 Retention Series', 10200.00, 225000, 18000, 1260, 113400.00
    UNION ALL SELECT 'Email', '2024-10-01', 'Q4 Holiday Push', 14000.00, 310000, 24800, 1736, 173600.00
    UNION ALL SELECT 'Email', '2024-11-01', 'Q4 Holiday Push', 16000.00, 350000, 28000, 1960, 196000.00
    UNION ALL SELECT 'Email', '2024-12-01', 'Q4 Holiday Push', 15000.00, 330000, 26400, 1848, 184800.00
    UNION ALL SELECT 'Display', '2024-01-01', 'Q1 Brand Awareness', 22000.00, 1200000, 6000, 180, 27000.00
    UNION ALL SELECT 'Display', '2024-02-01', 'Q1 Brand Awareness', 23000.00, 1250000, 6250, 188, 28125.00
    UNION ALL SELECT 'Display', '2024-03-01', 'Q1 Brand Awareness', 24000.00, 1300000, 6500, 195, 29250.00
    UNION ALL SELECT 'Display', '2024-04-01', 'Q2 Retargeting', 28000.00, 1500000, 7500, 225, 38250.00
    UNION ALL SELECT 'Display', '2024-05-01', 'Q2 Retargeting', 30000.00, 1600000, 8000, 240, 40800.00
    UNION ALL SELECT 'Display', '2024-06-01', 'Q2 Retargeting', 27000.00, 1450000, 7250, 218, 37005.00
    UNION ALL SELECT 'Display', '2024-07-01', 'H2 Programmatic', 25000.00, 1350000, 6750, 203, 32437.50
    UNION ALL SELECT 'Display', '2024-08-01', 'H2 Programmatic', 26000.00, 1400000, 7000, 210, 33600.00
    UNION ALL SELECT 'Display', '2024-09-01', 'H2 Programmatic', 27000.00, 1450000, 7250, 218, 34875.00
    UNION ALL SELECT 'Display', '2024-10-01', 'Q4 Holiday Push', 35000.00, 1850000, 9250, 278, 47175.00
    UNION ALL SELECT 'Display', '2024-11-01', 'Q4 Holiday Push', 40000.00, 2100000, 10500, 315, 53550.00
    UNION ALL SELECT 'Display', '2024-12-01', 'Q4 Holiday Push', 38000.00, 2000000, 10000, 300, 51000.00
) t
WHERE NOT EXISTS (SELECT 1 FROM CAMPAIGN_SPEND LIMIT 1);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. STRATEGY DOCUMENTS TABLE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS STRATEGY_DOCS (
    DOC_ID      VARCHAR,
    TITLE       VARCHAR,
    CONTENT     VARCHAR,
    DOC_TYPE    VARCHAR
);

INSERT INTO STRATEGY_DOCS
SELECT * FROM (
    SELECT 'DOC-001' AS DOC_ID, 'Channel Strategy 2024' AS TITLE, 'Our 2024 channel strategy focuses on a balanced portfolio approach across four primary channels: Paid Search, Social Media, Email, and Display. Paid Search remains our highest-performing channel for direct response and should receive 40% of total budget. Social Media is our primary brand awareness and community-building channel, allocated 25% of budget. Email remains the most cost-efficient channel with the highest conversion rates and receives 10% of budget. Display advertising supports retargeting and top-of-funnel awareness at 15% of budget. The remaining 10% is held as a flex budget for opportunistic campaigns and testing.' AS CONTENT, 'strategy' AS DOC_TYPE
    UNION ALL SELECT 'DOC-002', 'Attribution Methodology', 'We use a data-driven multi-touch attribution model that assigns credit to marketing touchpoints based on their actual contribution to conversions. The model uses a 30-day lookback window and applies diminishing returns to touchpoints further from conversion. First-touch receives a base weight of 0.2, last-touch receives 0.3, and middle touches share the remaining 0.5 proportional to their recency and engagement depth. Revenue attribution is calculated at the channel level by aggregating individual conversion paths. We report on both attributed revenue (model-based) and last-click revenue for comparison. All attribution data refreshes daily with a 48-hour lag for conversion window completion.', 'methodology'
    UNION ALL SELECT 'DOC-003', 'Q4 Planning Brief', 'Q4 2024 represents our peak revenue period with an expected 35% lift over Q3 baseline. Key initiatives include: (1) Holiday Push campaign across all channels starting October 1, (2) aggressive paid search bidding on Black Friday and Cyber Monday with 2x daily budgets, (3) email frequency increase to 3x per week during November-December, (4) social media influencer partnerships for holiday gift guides. Total Q4 budget is $590,000, a 45% increase over Q3. Success metrics: achieve ROAS of 3.5x or higher across the portfolio, maintain CPA below $45, and drive 15,000+ conversions across Q4.', 'brief'
    UNION ALL SELECT 'DOC-004', 'Budget Allocation Methodology', 'Budget allocation follows a performance-based model updated quarterly. We use three inputs to determine channel budgets: (1) Historical ROI by channel over the trailing 6 months, (2) Market opportunity size estimated via impression share and competitive intelligence, (3) Strategic priorities set by leadership for the planning period. Channels that exceed their ROI target by more than 20% receive automatic budget increases of up to 15% in the next period. Channels that underperform their ROI target by more than 20% for two consecutive periods trigger a review and potential reallocation. Minimum viable spend is maintained for all channels to preserve learnings and audience data.', 'methodology'
    UNION ALL SELECT 'DOC-005', 'Brand Guidelines for Reporting', 'All marketing performance reports must adhere to the following standards: (1) Currency should be reported in USD, rounded to 2 decimal places. (2) Percentages should be displayed to 1 decimal place. (3) When reporting ROI, use the formula: (Revenue - Spend) / Spend, expressed as a ratio (e.g., 3.2x not 320%). (4) Time periods must be explicitly stated in all data presentations. (5) Channel names must use official nomenclature: Paid Search, Social Media, Email, Display. (6) Year-over-year comparisons should note any methodology changes. (7) Executive summaries must lead with the single most impactful insight, followed by supporting data.', 'guidelines'
    UNION ALL SELECT 'DOC-006', 'Performance Benchmarks 2024', 'Internal benchmarks for 2024 marketing performance by channel. Paid Search: target CPC $3.00-$3.50, target conversion rate 5.0%, target ROAS 3.0x. Social Media: target CPC $3.50-$4.50, target conversion rate 4.0%, target ROAS 1.8x. Email: target open rate 8.0%, target conversion rate 7.0%, target ROAS 10.0x. Display: target CPM $18-$22, target conversion rate 3.0%, target ROAS 1.2x. These benchmarks are reviewed quarterly and adjusted based on market conditions and seasonal factors. Channels exceeding benchmarks by 20%+ are flagged for increased investment.', 'methodology'
) t
WHERE NOT EXISTS (SELECT 1 FROM STRATEGY_DOCS LIMIT 1);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. SEMANTIC VIEW (for Cortex Analyst)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SEMANTIC VIEW CMO_ANALYTICS
  COMMENT = 'Marketing campaign performance analytics for CMO assistant'
AS
  SELECT * FROM CAMPAIGN_SPEND
  WITH
    ENTITIES (
      channel ENTITY
        DESCRIPTION 'Marketing channel: Paid Search, Social Media, Email, or Display'
        COLUMNS (CHANNEL),
      month ENTITY
        DESCRIPTION 'Calendar month of the campaign spend'
        COLUMNS (MONTH),
      campaign ENTITY
        DESCRIPTION 'Named marketing campaign such as Q1 Brand Awareness or Q4 Holiday Push'
        COLUMNS (CAMPAIGN_NAME)
    )
    METRICS (
      total_spend METRIC
        DESCRIPTION 'Total marketing spend in USD'
        EXPRESSION 'SUM(SPEND)',
      total_revenue METRIC
        DESCRIPTION 'Total attributed revenue from marketing campaigns in USD'
        EXPRESSION 'SUM(REVENUE)',
      total_impressions METRIC
        DESCRIPTION 'Total number of ad impressions served'
        EXPRESSION 'SUM(IMPRESSIONS)',
      total_clicks METRIC
        DESCRIPTION 'Total number of clicks on ads'
        EXPRESSION 'SUM(CLICKS)',
      total_conversions METRIC
        DESCRIPTION 'Total number of conversions (purchases) attributed to marketing'
        EXPRESSION 'SUM(CONVERSIONS)',
      roi METRIC
        DESCRIPTION 'Return on investment calculated as (revenue - spend) / spend. Expressed as a multiplier (e.g., 3.2x means $3.20 return per $1 spent)'
        EXPRESSION '(SUM(REVENUE) - SUM(SPEND)) / NULLIF(SUM(SPEND), 0)',
      cpc METRIC
        DESCRIPTION 'Cost per click in USD'
        EXPRESSION 'SUM(SPEND) / NULLIF(SUM(CLICKS), 0)',
      cpa METRIC
        DESCRIPTION 'Cost per acquisition (cost per conversion) in USD'
        EXPRESSION 'SUM(SPEND) / NULLIF(SUM(CONVERSIONS), 0)',
      conversion_rate METRIC
        DESCRIPTION 'Conversion rate as a percentage of clicks that result in a purchase'
        EXPRESSION 'SUM(CONVERSIONS) / NULLIF(SUM(CLICKS), 0) * 100',
      roas METRIC
        DESCRIPTION 'Return on ad spend: revenue divided by spend'
        EXPRESSION 'SUM(REVENUE) / NULLIF(SUM(SPEND), 0)'
    )
    CUSTOM_INSTRUCTIONS = 'If no date filter is specified, default to the full year 2024. Always round currency values to 2 decimal places. When reporting ROI, express as a multiplier (e.g., 2.5x). Use official channel names: Paid Search, Social Media, Email, Display.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CORTEX SEARCH SERVICE (for RAG over strategy docs)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE CORTEX SEARCH SERVICE STRATEGY_SEARCH_SVC
  ON CONTENT
  ATTRIBUTES DOC_TYPE
  WAREHOUSE = CMO_EVAL_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT DOC_ID, TITLE, CONTENT, DOC_TYPE
  FROM STRATEGY_DOCS
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. EVALUATION INFRASTRUCTURE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FILE FORMAT YAML_FILE_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE;

CREATE OR REPLACE STAGE EVAL_STAGE
  FILE_FORMAT = YAML_FILE_FORMAT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. OBSERVABILITY MINING TABLES (new for this demo)
-- ─────────────────────────────────────────────────────────────────────────────

-- Table to store mined evaluation candidates from observability
CREATE OR REPLACE TABLE MINED_EVAL_CANDIDATES (
    CANDIDATE_ID        VARCHAR DEFAULT UUID_STRING(),
    SOURCE_TYPE         VARCHAR,  -- 'explicit_negative', 'explicit_positive', 'implicit_rephrase', 'intent_sample'
    USER_QUERY          VARCHAR,
    AGENT_RESPONSE      VARCHAR,
    FEEDBACK_SIGNAL     VARCHAR,  -- 'positive', 'negative', 'rephrase_detected'
    FEEDBACK_MESSAGE    VARCHAR,
    INTENT_CATEGORY     VARCHAR,
    SESSION_ID          VARCHAR,
    PRIORITY            VARCHAR,  -- 'high', 'medium', 'low'
    MINED_AT            TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    INCLUDED_IN_EVAL    BOOLEAN DEFAULT FALSE
);

-- Table for the final assembled evaluation dataset
CREATE OR REPLACE TABLE OBSERVABILITY_EVAL_DATASET (
    INPUT_QUERY     VARCHAR,
    GROUND_TRUTH    VARIANT,
    SOURCE          VARCHAR,  -- which mining technique produced this
    INTENT          VARCHAR,
    PRIORITY        VARCHAR
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. GRANTS
-- ─────────────────────────────────────────────────────────────────────────────

GRANT CREATE AGENT ON SCHEMA CMO_EVAL_LAB.PUBLIC TO ROLE SYSADMIN;
GRANT CREATE DATASET ON SCHEMA CMO_EVAL_LAB.PUBLIC TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 'Setup complete. Objects created in CMO_EVAL_LAB.PUBLIC.' AS STATUS;
