-- =============================================================================
-- Context-Scoped Cortex Agent Demo - Setup Script
-- =============================================================================
-- Run this script in your Snowflake account to create the demo database,
-- tables with mock data, and the semantic view used by the agent.
-- =============================================================================

USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS CORTEX_AGENT_DEMO;
CREATE SCHEMA IF NOT EXISTS CORTEX_AGENT_DEMO.ANALYTICS;
USE SCHEMA CORTEX_AGENT_DEMO.ANALYTICS;

-- =============================================================================
-- Table 1: MONTHLY_METRICS
-- Tracks high-level SaaS KPIs over time
-- =============================================================================

CREATE OR REPLACE TABLE MONTHLY_METRICS (
    MONTH_DATE DATE,
    MRR_USD NUMBER(12,2),
    CHURN_RATE_PCT NUMBER(5,2),
    NEW_CUSTOMERS INT,
    CHURNED_CUSTOMERS INT,
    ACTIVE_USERS INT,
    DAU INT,
    NET_REVENUE_RETENTION_PCT NUMBER(5,2)
);

INSERT INTO MONTHLY_METRICS VALUES
('2024-01-01', 1820000, 2.1, 45, 12, 12400, 8200, 108.5),
('2024-02-01', 1875000, 2.3, 52, 14, 12900, 8500, 107.2),
('2024-03-01', 1920000, 2.0, 48, 11, 13200, 8800, 109.1),
('2024-04-01', 1980000, 2.4, 55, 16, 13800, 9100, 106.8),
('2024-05-01', 2050000, 2.6, 61, 18, 14500, 9600, 105.4),
('2024-06-01', 2100000, 2.8, 58, 20, 15100, 10000, 104.9),
('2024-07-01', 2150000, 3.0, 50, 22, 15400, 10200, 104.2),
('2024-08-01', 2200000, 3.1, 53, 23, 15800, 10500, 103.8),
('2024-09-01', 2280000, 3.3, 62, 25, 16400, 10900, 103.1),
('2024-10-01', 2320000, 3.5, 58, 27, 16900, 11200, 102.5),
('2024-11-01', 2380000, 3.6, 64, 29, 17500, 11600, 101.9),
('2024-12-01', 2440000, 3.8, 68, 32, 18200, 12100, 101.2);

-- =============================================================================
-- Table 2: PIPELINE_STAGES
-- Tracks conversion funnel by segment and month
-- =============================================================================

CREATE OR REPLACE TABLE PIPELINE_STAGES (
    MONTH_DATE DATE,
    SEGMENT VARCHAR(50),
    STAGE_NAME VARCHAR(50),
    STAGE_ORDER INT,
    LEADS_COUNT INT,
    CONVERSION_RATE_PCT NUMBER(5,2),
    AVG_DEAL_SIZE_USD NUMBER(10,2),
    AVG_DAYS_IN_STAGE NUMBER(5,1)
);

INSERT INTO PIPELINE_STAGES VALUES
-- Enterprise - December 2024
('2024-12-01', 'Enterprise', 'Awareness', 1, 320, 100.0, 0, 0),
('2024-12-01', 'Enterprise', 'Interest', 2, 210, 65.6, 0, 12.5),
('2024-12-01', 'Enterprise', 'Evaluation', 3, 95, 45.2, 0, 28.3),
('2024-12-01', 'Enterprise', 'Negotiation', 4, 42, 44.2, 85000, 35.7),
('2024-12-01', 'Enterprise', 'Closed Won', 5, 28, 66.7, 92000, 14.2),
-- SMB - December 2024
('2024-12-01', 'SMB', 'Awareness', 1, 1200, 100.0, 0, 0),
('2024-12-01', 'SMB', 'Interest', 2, 680, 56.7, 0, 5.2),
('2024-12-01', 'SMB', 'Evaluation', 3, 290, 42.6, 0, 8.1),
('2024-12-01', 'SMB', 'Negotiation', 4, 145, 50.0, 12000, 6.3),
('2024-12-01', 'SMB', 'Closed Won', 5, 102, 70.3, 11500, 4.8),
-- Mid-Market - December 2024
('2024-12-01', 'Mid-Market', 'Awareness', 1, 580, 100.0, 0, 0),
('2024-12-01', 'Mid-Market', 'Interest', 2, 350, 60.3, 0, 8.1),
('2024-12-01', 'Mid-Market', 'Evaluation', 3, 160, 45.7, 0, 15.4),
('2024-12-01', 'Mid-Market', 'Negotiation', 4, 78, 48.8, 35000, 18.2),
('2024-12-01', 'Mid-Market', 'Closed Won', 5, 52, 66.7, 38000, 9.5),
-- Enterprise - November 2024
('2024-11-01', 'Enterprise', 'Awareness', 1, 290, 100.0, 0, 0),
('2024-11-01', 'Enterprise', 'Interest', 2, 195, 67.2, 0, 11.8),
('2024-11-01', 'Enterprise', 'Evaluation', 3, 88, 45.1, 0, 26.5),
('2024-11-01', 'Enterprise', 'Negotiation', 4, 38, 43.2, 82000, 33.1),
('2024-11-01', 'Enterprise', 'Closed Won', 5, 24, 63.2, 88000, 15.8),
-- SMB - November 2024
('2024-11-01', 'SMB', 'Awareness', 1, 1100, 100.0, 0, 0),
('2024-11-01', 'SMB', 'Interest', 2, 620, 56.4, 0, 5.5),
('2024-11-01', 'SMB', 'Evaluation', 3, 265, 42.7, 0, 7.8),
('2024-11-01', 'SMB', 'Negotiation', 4, 130, 49.1, 11800, 6.1),
('2024-11-01', 'SMB', 'Closed Won', 5, 88, 67.7, 11200, 5.0),
-- Mid-Market - November 2024
('2024-11-01', 'Mid-Market', 'Awareness', 1, 540, 100.0, 0, 0),
('2024-11-01', 'Mid-Market', 'Interest', 2, 320, 59.3, 0, 7.9),
('2024-11-01', 'Mid-Market', 'Evaluation', 3, 145, 45.3, 0, 14.8),
('2024-11-01', 'Mid-Market', 'Negotiation', 4, 70, 48.3, 33000, 17.5),
('2024-11-01', 'Mid-Market', 'Closed Won', 5, 45, 64.3, 36000, 10.2);

-- =============================================================================
-- Table 3: CUSTOMER_SEGMENTS
-- Describes each customer segment and its current attributes
-- =============================================================================

CREATE OR REPLACE TABLE CUSTOMER_SEGMENTS (
    SEGMENT_NAME VARCHAR(100),
    REGION VARCHAR(50),
    CUSTOMER_COUNT INT,
    AVG_DEAL_SIZE_USD NUMBER(10,2),
    RETENTION_RATE_PCT NUMBER(5,2),
    AVG_NPS_SCORE NUMBER(4,1),
    MONTHLY_ACTIVE_RATE_PCT NUMBER(5,2),
    TOP_FEATURE_USED VARCHAR(100),
    EXPANSION_REVENUE_PCT NUMBER(5,2),
    SUPPORT_TICKETS_PER_MONTH NUMBER(5,1)
);

INSERT INTO CUSTOMER_SEGMENTS VALUES
('Enterprise US West', 'US West', 85, 95000, 96.2, 72.5, 88.3, 'Advanced Analytics', 12.4, 2.1),
('Enterprise US East', 'US East', 110, 88000, 94.8, 68.2, 85.1, 'Custom Dashboards', 10.8, 3.4),
('Enterprise EMEA', 'EMEA', 62, 78000, 93.5, 65.8, 82.7, 'Data Export', 9.2, 4.2),
('Mid-Market US', 'US', 245, 36000, 91.2, 62.4, 78.5, 'Team Collaboration', 7.5, 2.8),
('Mid-Market EMEA', 'EMEA', 180, 32000, 89.8, 60.1, 75.2, 'Reporting', 6.8, 3.5),
('SMB US', 'US', 820, 11500, 85.4, 58.2, 68.4, 'Basic Dashboards', 4.2, 1.5),
('SMB EMEA', 'EMEA', 540, 10200, 83.1, 55.8, 64.2, 'Basic Dashboards', 3.8, 1.8),
('SMB APAC', 'APAC', 320, 9800, 81.5, 54.2, 61.8, 'Reporting', 3.2, 2.2);

-- =============================================================================
-- Semantic View: ANALYTICS_ASSISTANT
-- Single unified semantic view covering all three tables
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW CORTEX_AGENT_DEMO.ANALYTICS.ANALYTICS_ASSISTANT
  TABLES (
    MONTHLY_METRICS AS CORTEX_AGENT_DEMO.ANALYTICS.MONTHLY_METRICS
      PRIMARY KEY (MONTH_DATE)
      WITH SYNONYMS = ('monthly kpis', 'saas metrics', 'revenue metrics', 'company metrics')
      COMMENT = 'Monthly SaaS KPIs including MRR, churn, and user engagement',
    PIPELINE_STAGES AS CORTEX_AGENT_DEMO.ANALYTICS.PIPELINE_STAGES
      WITH SYNONYMS = ('funnel', 'sales pipeline', 'conversion funnel', 'leads')
      COMMENT = 'Sales pipeline conversion data by segment and stage',
    CUSTOMER_SEGMENTS AS CORTEX_AGENT_DEMO.ANALYTICS.CUSTOMER_SEGMENTS
      PRIMARY KEY (SEGMENT_NAME)
      WITH SYNONYMS = ('segments', 'cohorts', 'customer cohorts', 'customer groups')
      COMMENT = 'Customer segment profiles with engagement and revenue metrics'
  )
  RELATIONSHIPS (
    pipeline_to_segments AS
      PIPELINE_STAGES (SEGMENT) REFERENCES CUSTOMER_SEGMENTS (SEGMENT_NAME),
    pipeline_to_metrics AS
      PIPELINE_STAGES (MONTH_DATE) REFERENCES MONTHLY_METRICS (MONTH_DATE)
  )
  FACTS (
    MONTHLY_METRICS.MRR_USD_FACT AS MRR_USD
      WITH SYNONYMS = ('MRR', 'monthly recurring revenue', 'recurring revenue')
      COMMENT = 'Monthly recurring revenue in US dollars',
    MONTHLY_METRICS.CHURN_RATE_PCT_FACT AS CHURN_RATE_PCT
      WITH SYNONYMS = ('churn', 'churn rate', 'customer churn')
      COMMENT = 'Percentage of customers lost in the month',
    MONTHLY_METRICS.NEW_CUSTOMERS_FACT AS NEW_CUSTOMERS
      WITH SYNONYMS = ('new logos', 'new accounts', 'acquisitions')
      COMMENT = 'Number of new customers acquired in the month',
    MONTHLY_METRICS.CHURNED_CUSTOMERS_FACT AS CHURNED_CUSTOMERS
      WITH SYNONYMS = ('lost customers', 'cancelled')
      COMMENT = 'Number of customers who churned in the month',
    MONTHLY_METRICS.ACTIVE_USERS_FACT AS ACTIVE_USERS
      WITH SYNONYMS = ('MAU', 'monthly active users')
      COMMENT = 'Total monthly active users',
    MONTHLY_METRICS.DAU_FACT AS DAU
      WITH SYNONYMS = ('daily active users')
      COMMENT = 'Average daily active users for the month',
    MONTHLY_METRICS.NET_REVENUE_RETENTION_PCT_FACT AS NET_REVENUE_RETENTION_PCT
      WITH SYNONYMS = ('NRR', 'net retention', 'dollar retention')
      COMMENT = 'Net revenue retention percentage including expansion',
    PIPELINE_STAGES.LEADS_COUNT_FACT AS LEADS_COUNT
      WITH SYNONYMS = ('leads', 'opportunities', 'deals')
      COMMENT = 'Number of leads/opportunities at this stage',
    PIPELINE_STAGES.CONVERSION_RATE_PCT_FACT AS CONVERSION_RATE_PCT
      WITH SYNONYMS = ('conversion rate', 'win rate')
      COMMENT = 'Conversion rate from previous stage to this stage',
    PIPELINE_STAGES.AVG_DEAL_SIZE_USD_FACT AS AVG_DEAL_SIZE_USD
      WITH SYNONYMS = ('deal size', 'average contract value', 'ACV')
      COMMENT = 'Average deal size in USD at this stage (0 for early stages)',
    PIPELINE_STAGES.AVG_DAYS_IN_STAGE_FACT AS AVG_DAYS_IN_STAGE
      WITH SYNONYMS = ('cycle time', 'time in stage', 'velocity')
      COMMENT = 'Average days a lead spends in this stage',
    CUSTOMER_SEGMENTS.CUSTOMER_COUNT_FACT AS CUSTOMER_COUNT
      WITH SYNONYMS = ('customers', 'accounts', 'logos')
      COMMENT = 'Number of customers in this segment',
    CUSTOMER_SEGMENTS.SEGMENT_AVG_DEAL_SIZE AS AVG_DEAL_SIZE_USD
      WITH SYNONYMS = ('segment deal size', 'segment ACV')
      COMMENT = 'Average deal size for this segment',
    CUSTOMER_SEGMENTS.RETENTION_RATE_PCT_FACT AS RETENTION_RATE_PCT
      WITH SYNONYMS = ('retention', 'logo retention')
      COMMENT = 'Customer retention rate for this segment',
    CUSTOMER_SEGMENTS.AVG_NPS_SCORE_FACT AS AVG_NPS_SCORE
      WITH SYNONYMS = ('NPS', 'net promoter score', 'satisfaction')
      COMMENT = 'Average NPS score for this segment',
    CUSTOMER_SEGMENTS.MONTHLY_ACTIVE_RATE_PCT_FACT AS MONTHLY_ACTIVE_RATE_PCT
      WITH SYNONYMS = ('engagement rate', 'activity rate')
      COMMENT = 'Percentage of customers actively using the product monthly',
    CUSTOMER_SEGMENTS.EXPANSION_REVENUE_PCT_FACT AS EXPANSION_REVENUE_PCT
      WITH SYNONYMS = ('expansion', 'upsell rate', 'growth rate')
      COMMENT = 'Revenue expansion percentage from existing customers',
    CUSTOMER_SEGMENTS.SUPPORT_TICKETS_PER_MONTH_FACT AS SUPPORT_TICKETS_PER_MONTH
      WITH SYNONYMS = ('support volume', 'ticket volume')
      COMMENT = 'Average support tickets per customer per month'
  )
  DIMENSIONS (
    MONTHLY_METRICS.MONTH_DATE_DIM AS MONTH_DATE
      WITH SYNONYMS = ('month', 'date', 'period', 'time')
      COMMENT = 'First day of the month for the metric period',
    PIPELINE_STAGES.SEGMENT_DIM AS SEGMENT
      WITH SYNONYMS = ('customer segment', 'market segment')
      COMMENT = 'Market segment: Enterprise, Mid-Market, or SMB',
    PIPELINE_STAGES.STAGE_NAME_DIM AS STAGE_NAME
      WITH SYNONYMS = ('funnel stage', 'pipeline stage', 'deal stage')
      COMMENT = 'Name of the pipeline stage',
    PIPELINE_STAGES.STAGE_ORDER_DIM AS STAGE_ORDER
      COMMENT = 'Numeric order of the stage in the funnel (1=top)',
    PIPELINE_STAGES.PIPELINE_MONTH_DIM AS MONTH_DATE
      WITH SYNONYMS = ('pipeline month', 'pipeline date')
      COMMENT = 'Month of the pipeline data',
    CUSTOMER_SEGMENTS.SEGMENT_NAME_DIM AS SEGMENT_NAME
      WITH SYNONYMS = ('segment', 'cohort name')
      COMMENT = 'Name of the customer segment (e.g., Enterprise US West)',
    CUSTOMER_SEGMENTS.REGION_DIM AS REGION
      WITH SYNONYMS = ('geography', 'geo', 'market')
      COMMENT = 'Geographic region of the segment',
    CUSTOMER_SEGMENTS.TOP_FEATURE_USED_DIM AS TOP_FEATURE_USED
      WITH SYNONYMS = ('most used feature', 'popular feature')
      COMMENT = 'The most-used product feature in this segment'
  )
  METRICS (
    MONTHLY_METRICS.TOTAL_MRR AS SUM(MONTHLY_METRICS.MRR_USD_FACT)
      COMMENT = 'Total MRR across all months',
    MONTHLY_METRICS.AVG_CHURN_RATE AS AVG(MONTHLY_METRICS.CHURN_RATE_PCT_FACT)
      COMMENT = 'Average churn rate',
    MONTHLY_METRICS.TOTAL_NEW_CUSTOMERS AS SUM(MONTHLY_METRICS.NEW_CUSTOMERS_FACT)
      COMMENT = 'Total new customers acquired',
    PIPELINE_STAGES.TOTAL_LEADS AS SUM(PIPELINE_STAGES.LEADS_COUNT_FACT)
      COMMENT = 'Total leads across stages',
    CUSTOMER_SEGMENTS.TOTAL_CUSTOMERS AS SUM(CUSTOMER_SEGMENTS.CUSTOMER_COUNT_FACT)
      COMMENT = 'Total customers across segments'
  )
  COMMENT = 'Unified analytics semantic view for SaaS metrics, pipeline, and customer segments';

-- =============================================================================
-- Agent: ANALYTICS_AGENT
-- Pre-configured agent with tools, model, and base instructions
-- =============================================================================

CREATE OR REPLACE AGENT CORTEX_AGENT_DEMO.ANALYTICS.ANALYTICS_AGENT
  COMMENT = 'Context-scoped analytics agent for demo'
  FROM SPECIFICATION
  $$
  models:
    orchestration: claude-sonnet-4-5

  instructions:
    response: >
      You are an AI assistant embedded in a SaaS analytics platform.
      You help users understand their data by answering questions about metrics,
      pipeline performance, and customer segments. Be concise and actionable.
      When referencing data, cite specific numbers.

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "analyst_tool"
        description: "Query SaaS metrics, pipeline stages, and customer segments"

  tool_resources:
    analyst_tool:
      semantic_view: "CORTEX_AGENT_DEMO.ANALYTICS.ANALYTICS_ASSISTANT"
      execution_environment:
        type: "warehouse"
        warehouse: "COMPUTE_WH"
  $$;

-- =============================================================================
-- Streamlit App: CONTEXT_SCOPED_AGENT_DEMO
-- Deploy via CLI: snow streamlit deploy --replace --connection <conn>
-- The CREATE STREAMLIT below documents the object; files are uploaded by the CLI.
-- =============================================================================

CREATE STREAMLIT IF NOT EXISTS CORTEX_AGENT_DEMO.ANALYTICS.CONTEXT_SCOPED_AGENT_DEMO
  ROOT_LOCATION = '@CORTEX_AGENT_DEMO.ANALYTICS.CONTEXT_SCOPED_AGENT_DEMO/versions/live'
  MAIN_FILE = 'app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  COMMENT = 'Context-scoped Cortex Agent demo app';

-- Grant usage for demo purposes
GRANT USAGE ON DATABASE CORTEX_AGENT_DEMO TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA CORTEX_AGENT_DEMO.ANALYTICS TO ROLE PUBLIC;
GRANT SELECT ON ALL TABLES IN SCHEMA CORTEX_AGENT_DEMO.ANALYTICS TO ROLE PUBLIC;
GRANT REFERENCES, SELECT ON SEMANTIC VIEW CORTEX_AGENT_DEMO.ANALYTICS.ANALYTICS_ASSISTANT TO ROLE PUBLIC;
GRANT USAGE ON AGENT CORTEX_AGENT_DEMO.ANALYTICS.ANALYTICS_AGENT TO ROLE PUBLIC;
GRANT USAGE ON STREAMLIT CORTEX_AGENT_DEMO.ANALYTICS.CONTEXT_SCOPED_AGENT_DEMO TO ROLE PUBLIC;