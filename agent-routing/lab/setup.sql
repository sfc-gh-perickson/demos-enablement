-- =============================================================================
-- Server-Side Agent Routing Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, warehouse, specialist agents,
-- wrapper procedures, supervisor agent, and evaluation infrastructure.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE privileges
--   - Cross-region inference enabled (for agent evaluation LLM judges)
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS ROUTING_DEMO;
USE DATABASE ROUTING_DEMO;
CREATE SCHEMA IF NOT EXISTS ROUTING;
USE SCHEMA ROUTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS ROUTING_DEMO_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE ROUTING_DEMO_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SPECIALIST AGENTS
-- ─────────────────────────────────────────────────────────────────────────────

-- Specialist Agent 1: Sales Analyst
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SALES_ANALYST
COMMENT = 'Sales specialist for revenue, pipeline, quotas, and forecasts'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Sales Analyst. You answer questions about revenue, pipeline,
    quotas, forecasts, channel performance, pricing strategy, deal velocity,
    and growth rates. Provide specific numbers when possible.
  orchestration: "Answer sales-related questions using available tools."
tools:
  - tool_spec:
      type: "code_execution"
      name: "python_sandbox"
$$;

-- Specialist Agent 2: Product Support
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.PRODUCT_SUPPORT
COMMENT = 'Product specialist for troubleshooting, specs, and warranty'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Product Support specialist. You answer questions about product
    specifications, troubleshooting steps, warranty policies, feature comparisons,
    known issues, and user guides.
  orchestration: "Answer product support questions comprehensively."
tools:
  - tool_spec:
      type: "code_execution"
      name: "python_sandbox"
$$;

-- Specialist Agent 3: Supply Chain
CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SUPPLY_CHAIN
COMMENT = 'Supply chain specialist for inventory, logistics, and procurement'
FROM SPECIFICATION $$
models:
  orchestration: auto
instructions:
  response: |
    You are the Supply Chain agent. You answer questions about inventory levels,
    lead times, supplier performance, fulfillment rates, warehouse capacity,
    shipping logistics, and procurement optimization.
  orchestration: "Answer supply chain and logistics questions."
tools:
  - tool_spec:
      type: "code_execution"
      name: "python_sandbox"
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. STORED PROCEDURE WRAPPERS
-- ─────────────────────────────────────────────────────────────────────────────
-- Each specialist is wrapped in an EXECUTE AS OWNER procedure that calls
-- DATA_AGENT_RUN. The supervisor invokes these as tools — routing happens
-- server-side regardless of which client calls the supervisor.

-- Wrapper for Sales Analyst
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SALES_AGENT(query VARCHAR)
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

def run(session, query):
    body = json.dumps({
        "messages": [{"role": "user", "content": [{"type": "text", "text": query}]}]
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.SALES_ANALYST',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- Wrapper for Product Support
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_PRODUCT_AGENT(query VARCHAR)
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

def run(session, query):
    body = json.dumps({
        "messages": [{"role": "user", "content": [{"type": "text", "text": query}]}]
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.PRODUCT_SUPPORT',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- Wrapper for Supply Chain
CREATE OR REPLACE PROCEDURE ROUTING_DEMO.ROUTING.RUN_SUPPLY_CHAIN_AGENT(query VARCHAR)
  RETURNS VARCHAR
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.11'
  PACKAGES = ('snowflake-snowpark-python')
  HANDLER = 'run'
  EXECUTE AS OWNER
AS
$$
import json

def run(session, query):
    body = json.dumps({
        "messages": [{"role": "user", "content": [{"type": "text", "text": query}]}]
    })
    escaped = body.replace("'", "''")
    result = session.sql(
        f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN("
        f"  'ROUTING_DEMO.ROUTING.SUPPLY_CHAIN',"
        f"  '{escaped}'"
        f")"
    ).collect()
    return str(result[0][0]) if result else ''
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SUPERVISOR AGENT (single entry point for all clients)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE AGENT ROUTING_DEMO.ROUTING.SUPERVISOR
COMMENT = 'Server-side routing agent — eliminates cross-surface variance'
FROM SPECIFICATION $$
models:
  orchestration: auto
orchestration:
  budget:
    seconds: 120
    tokens: 12000
instructions:
  response: |
    You are an enterprise routing agent. Your job is to route each user question
    to the correct specialist and return their response directly. Do not add your
    own commentary — relay the specialist's answer faithfully.
  orchestration: |
    You have access to three specialist agents. Route each user question to the
    SINGLE most appropriate specialist:

    - sales_agent: Revenue, pipeline, quotas, forecasts, channel performance,
      pricing, deals, margins, growth rates, sales targets
    - product_agent: Product specifications, troubleshooting, warranty policies,
      feature comparisons, known issues, user guides, product setup
    - supply_chain_agent: Inventory levels, lead times, supplier performance,
      fulfillment rates, logistics, shipping, warehouse capacity, procurement

    ALWAYS call exactly one specialist per question. Pass the user's full
    question as the message parameter. Return the specialist's response to the user.
tools:
  - tool_spec:
      type: generic
      name: sales_agent
      description: "Routes to the Sales Analyst for questions about revenue, pipeline, quotas, forecasts, channel performance, pricing, and deals"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's sales-related question"
        required: ["message"]
  - tool_spec:
      type: generic
      name: product_agent
      description: "Routes to Product Support for questions about product specs, troubleshooting, warranty, feature comparisons, and known issues"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's product-related question"
        required: ["message"]
  - tool_spec:
      type: generic
      name: supply_chain_agent
      description: "Routes to Supply Chain for questions about inventory, lead times, supplier performance, fulfillment, logistics, and shipping"
      input_schema:
        type: object
        properties:
          message:
            type: string
            description: "The user's supply chain question"
        required: ["message"]
tool_resources:
  sales_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_SALES_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
  product_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_PRODUCT_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
  supply_chain_agent:
    type: procedure
    identifier: ROUTING_DEMO.ROUTING.RUN_SUPPLY_CHAIN_AGENT
    execution_environment:
      type: warehouse
      warehouse: ROUTING_DEMO_WH
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. EVALUATION INFRASTRUCTURE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FILE FORMAT ROUTING_DEMO.ROUTING.YAML_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = NONE
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = NONE
  ESCAPE_UNENCLOSED_FIELD = NONE;

CREATE OR REPLACE STAGE ROUTING_DEMO.ROUTING.EVAL_STAGE
  FILE_FORMAT = ROUTING_DEMO.ROUTING.YAML_FORMAT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. EVALUATION DATASET (6 rows: 2 per domain)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE ROUTING_DEMO.ROUTING.EVAL_DATA (
    input_query VARCHAR,
    ground_truth VARIANT
);

INSERT INTO ROUTING_DEMO.ROUTING.EVAL_DATA
SELECT column1, PARSE_JSON(column2) FROM VALUES
-- Sales queries → should route to sales_agent
('What was our Q1 2025 revenue by product line?',
 '{"ground_truth_output": "The response should provide revenue figures broken down by product line for Q1 2025, including specific dollar amounts.", "ground_truth_invocations": [{"tool_name": "sales_agent", "tool_input": "Q1 2025 revenue by product line"}]}'),

('How is our pipeline tracking against the Q2 quota?',
 '{"ground_truth_output": "The response should compare current pipeline value against the Q2 sales quota, noting coverage ratio and risk areas.", "ground_truth_invocations": [{"tool_name": "sales_agent", "tool_input": "Pipeline tracking against Q2 quota"}]}'),

-- Product queries → should route to product_agent
('My device keeps disconnecting from WiFi after the latest firmware update. What should I try?',
 '{"ground_truth_output": "The response should provide WiFi troubleshooting steps such as resetting network settings, checking router compatibility, or rolling back firmware.", "ground_truth_invocations": [{"tool_name": "product_agent", "tool_input": "Device WiFi disconnection after firmware update troubleshooting"}]}'),

('What warranty coverage applies to accessories purchased separately?',
 '{"ground_truth_output": "The response should describe warranty terms for separately purchased accessories, including duration and what is covered.", "ground_truth_invocations": [{"tool_name": "product_agent", "tool_input": "Warranty coverage for separately purchased accessories"}]}'),

-- Supply chain queries → should route to supply_chain_agent
('What is our current inventory level for the top-selling SKU?',
 '{"ground_truth_output": "The response should provide current inventory data or stock levels for the top-selling SKU across warehouses or channels.", "ground_truth_invocations": [{"tool_name": "supply_chain_agent", "tool_input": "Current inventory level for top-selling SKU"}]}'),

('What are the average lead times from our Southeast Asia suppliers?',
 '{"ground_truth_output": "The response should provide lead time estimates from Southeast Asia suppliers, ideally broken down by product category or shipping method.", "ground_truth_invocations": [{"tool_name": "supply_chain_agent", "tool_input": "Average lead times from Southeast Asia suppliers"}]}')

AS t(column1, column2);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. EVALUATION CONFIG YAML (upload to stage via notebook)
-- ─────────────────────────────────────────────────────────────────────────────
-- The eval config YAML is uploaded programmatically in the lab notebook.
-- For reference, the config should contain:
--
--   evaluation:
--     agent_params:
--       agent_name: "ROUTING_DEMO.ROUTING.SUPERVISOR"
--       agent_type: "CORTEX AGENT"
--     run_params:
--       label: "Routing quality baseline"
--       description: "Validates that the supervisor routes to the correct specialist"
--     source_metadata:
--       type: "dataset"
--       dataset_name: "ROUTING_DEMO.ROUTING.ROUTING_EVAL_DATASET"
--
--   metrics:
--     - "answer_correctness"
--     - "tool_selection_accuracy"
--     - "logical_consistency"

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. GRANTS (ensure evaluation permissions)
-- ─────────────────────────────────────────────────────────────────────────────

-- Grant required permissions for agent evaluation
-- (Run as ACCOUNTADMIN or adjust for your role)
GRANT CREATE AGENT ON SCHEMA ROUTING_DEMO.ROUTING TO ROLE SYSADMIN;
GRANT CREATE DATASET ON SCHEMA ROUTING_DEMO.ROUTING TO ROLE SYSADMIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify all objects were created:
SHOW AGENTS IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW PROCEDURES IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW TABLES IN SCHEMA ROUTING_DEMO.ROUTING;
SHOW STAGES IN SCHEMA ROUTING_DEMO.ROUTING;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- You can now proceed to the lab notebook. All objects are in place:
--   - 3 specialist agents (SALES_ANALYST, PRODUCT_SUPPORT, SUPPLY_CHAIN)
--   - 3 wrapper procedures (RUN_SALES_AGENT, RUN_PRODUCT_AGENT, RUN_SUPPLY_CHAIN_AGENT)
--   - 1 supervisor agent (SUPERVISOR)
--   - 1 evaluation table (EVAL_DATA) with 6 ground truth rows
--   - 1 internal stage (EVAL_STAGE) for YAML configs
