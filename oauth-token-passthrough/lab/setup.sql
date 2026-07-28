-- OAuth Token Passthrough Lab: Setup Script
-- Co-authored with CoCo
-- ====================================================

-- Run this script once before starting the notebook.
-- It creates all prerequisite objects: database, tables, External OAuth
-- security integration, semantic view, and Cortex Agent.
--
-- Prerequisites:
--   - ACCOUNTADMIN role (for security integration creation)
--   - An Entra ID (Azure AD) tenant with an app registration
--   - SNOWFLAKE.CORTEX_USER database role granted to your role
--   - Cross-region inference enabled (for agent LLM calls)
--
-- IMPORTANT: Replace <your-tenant-id> with your actual Entra ID tenant ID
--            Replace <your-audience-uri> with your app registration's Application ID URI
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS OAUTH_PASSTHROUGH_LAB;
USE DATABASE OAUTH_PASSTHROUGH_LAB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;
USE SCHEMA PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────

CREATE WAREHOUSE IF NOT EXISTS OAUTH_PASSTHROUGH_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE OAUTH_PASSTHROUGH_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. EXTERNAL OAUTH SECURITY INTEGRATION (Entra ID)
-- ─────────────────────────────────────────────────────────────────────────────
-- This is the centerpiece of the lab. It tells Snowflake how to validate
-- OAuth tokens issued by your Entra ID tenant.
--
-- How it works:
--   1. A client (e.g., Teams bot via AgentCore) obtains an access token from Entra ID
--   2. The client passes that token as a Bearer token to Snowflake's REST API
--   3. Snowflake validates the token using the JWKS URL and issuer
--   4. Snowflake maps the token's UPN claim to a Snowflake user (via login_name)
--   5. The session runs as that mapped user with their granted roles

CREATE OR REPLACE SECURITY INTEGRATION OAUTH_ENTRA_ID_PASSTHROUGH
  TYPE = EXTERNAL_OAUTH
  ENABLED = TRUE
  EXTERNAL_OAUTH_TYPE = AZURE
  EXTERNAL_OAUTH_ISSUER = 'https://sts.windows.net/<your-tenant-id>/'
  EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://login.microsoftonline.com/<your-tenant-id>/discovery/v2.0/keys'
  EXTERNAL_OAUTH_AUDIENCE_LIST = ('<your-audience-uri>')
  EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'upn'
  EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'login_name'
  EXTERNAL_OAUTH_ANY_ROLE_MODE = 'ENABLE';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DEMO TABLE: CUSTOMER_SUPPORT_TICKETS
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE CUSTOMER_SUPPORT_TICKETS (
    TICKET_ID       NUMBER,
    CUSTOMER_NAME   VARCHAR,
    CUSTOMER_EMAIL  VARCHAR,
    PRIORITY        VARCHAR,
    STATUS          VARCHAR,
    CATEGORY        VARCHAR,
    CREATED_DATE    DATE,
    RESOLVED_DATE   DATE,
    AGENT_NAME      VARCHAR,
    SATISFACTION    NUMBER(2,1)
);

INSERT INTO CUSTOMER_SUPPORT_TICKETS VALUES
(5001, 'Alice Johnson', 'alice.johnson@contoso.com', 'High', 'Resolved', 'Billing', '2024-01-05', '2024-01-06', 'Support Agent A', 4.5),
(5002, 'Bob Smith', 'bob.smith@contoso.com', 'Medium', 'Resolved', 'Technical', '2024-01-08', '2024-01-10', 'Support Agent B', 3.8),
(5003, 'Carol White', 'carol.white@contoso.com', 'Low', 'Resolved', 'General', '2024-01-12', '2024-01-14', 'Support Agent A', 4.2),
(5004, 'David Lee', 'david.lee@contoso.com', 'High', 'Resolved', 'Technical', '2024-01-15', '2024-01-16', 'Support Agent C', 4.8),
(5005, 'Eva Martinez', 'eva.martinez@contoso.com', 'Medium', 'Resolved', 'Billing', '2024-01-20', '2024-01-22', 'Support Agent B', 3.5),
(5006, 'Frank Chen', 'frank.chen@contoso.com', 'High', 'Resolved', 'Technical', '2024-02-01', '2024-02-02', 'Support Agent A', 4.7),
(5007, 'Grace Kim', 'grace.kim@contoso.com', 'Low', 'Resolved', 'General', '2024-02-05', '2024-02-08', 'Support Agent C', 4.0),
(5008, 'Henry Wilson', 'henry.wilson@contoso.com', 'Medium', 'Resolved', 'Billing', '2024-02-10', '2024-02-12', 'Support Agent B', 3.9),
(5009, 'Irene Davis', 'irene.davis@contoso.com', 'High', 'Resolved', 'Technical', '2024-02-15', '2024-02-16', 'Support Agent A', 4.6),
(5010, 'Jack Brown', 'jack.brown@contoso.com', 'Medium', 'Resolved', 'General', '2024-02-20', '2024-02-23', 'Support Agent C', 4.1),
(5011, 'Karen Taylor', 'karen.taylor@contoso.com', 'High', 'Resolved', 'Technical', '2024-03-01', '2024-03-02', 'Support Agent A', 4.9),
(5012, 'Leo Nguyen', 'leo.nguyen@contoso.com', 'Low', 'Resolved', 'Billing', '2024-03-05', '2024-03-08', 'Support Agent B', 3.6),
(5013, 'Maya Patel', 'maya.patel@contoso.com', 'Medium', 'Resolved', 'Technical', '2024-03-10', '2024-03-12', 'Support Agent C', 4.3),
(5014, 'Nick Adams', 'nick.adams@contoso.com', 'High', 'Resolved', 'Billing', '2024-03-15', '2024-03-16', 'Support Agent A', 4.4),
(5015, 'Olivia Ross', 'olivia.ross@contoso.com', 'Medium', 'Resolved', 'General', '2024-03-20', '2024-03-22', 'Support Agent B', 4.0),
(5016, 'Paul Garcia', 'paul.garcia@contoso.com', 'Low', 'Resolved', 'Technical', '2024-04-01', '2024-04-04', 'Support Agent C', 3.7),
(5017, 'Quinn Foster', 'quinn.foster@contoso.com', 'High', 'Resolved', 'Billing', '2024-04-05', '2024-04-06', 'Support Agent A', 4.8),
(5018, 'Rachel Park', 'rachel.park@contoso.com', 'Medium', 'Resolved', 'Technical', '2024-04-10', '2024-04-12', 'Support Agent B', 4.2),
(5019, 'Sam Turner', 'sam.turner@contoso.com', 'High', 'Resolved', 'General', '2024-04-15', '2024-04-16', 'Support Agent C', 4.5),
(5020, 'Tina Walker', 'tina.walker@contoso.com', 'Medium', 'Resolved', 'Technical', '2024-04-20', '2024-04-22', 'Support Agent A', 4.1),
(5021, 'Uma Shah', 'uma.shah@contoso.com', 'Low', 'Open', 'Billing', '2024-05-01', NULL, 'Support Agent B', NULL),
(5022, 'Victor Liu', 'victor.liu@contoso.com', 'High', 'Open', 'Technical', '2024-05-05', NULL, 'Support Agent C', NULL),
(5023, 'Wendy Clark', 'wendy.clark@contoso.com', 'Medium', 'Open', 'General', '2024-05-10', NULL, 'Support Agent A', NULL),
(5024, 'Xavier Moore', 'xavier.moore@contoso.com', 'High', 'In Progress', 'Technical', '2024-05-12', NULL, 'Support Agent B', NULL),
(5025, 'Yara Diaz', 'yara.diaz@contoso.com', 'Low', 'In Progress', 'Billing', '2024-05-15', NULL, 'Support Agent C', NULL);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SEMANTIC VIEW
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE SEMANTIC VIEW SUPPORT_TICKET_ANALYTICS
  TABLES (
    OAUTH_PASSTHROUGH_LAB.PUBLIC.CUSTOMER_SUPPORT_TICKETS
  )
  DIMENSIONS (
    CUSTOMER_SUPPORT_TICKETS.PRIORITY AS PRIORITY comment='Ticket priority: High, Medium, or Low',
    CUSTOMER_SUPPORT_TICKETS.STATUS AS STATUS comment='Ticket status: Open, In Progress, or Resolved',
    CUSTOMER_SUPPORT_TICKETS.CATEGORY AS CATEGORY comment='Support category: Technical, Billing, or General',
    CUSTOMER_SUPPORT_TICKETS.CREATED_DATE AS CREATED_DATE comment='Date the ticket was created',
    CUSTOMER_SUPPORT_TICKETS.AGENT_NAME AS AGENT_NAME comment='Name of the support agent handling the ticket'
  )
  METRICS (
    CUSTOMER_SUPPORT_TICKETS.TICKET_COUNT AS COUNT(*) comment='Total number of support tickets',
    CUSTOMER_SUPPORT_TICKETS.AVG_SATISFACTION AS AVG(SATISFACTION) comment='Average customer satisfaction score (1-5 scale)',
    CUSTOMER_SUPPORT_TICKETS.HIGH_PRIORITY_COUNT AS COUNT_IF(PRIORITY = 'High') comment='Number of high-priority tickets'
  )
  COMMENT = 'Customer support ticket analytics for OAuth passthrough demo'
  AI_SQL_GENERATION 'This table contains customer support tickets. When asked about resolution time, calculate the difference between RESOLVED_DATE and CREATED_DATE. Round satisfaction scores to 1 decimal place. Tickets with NULL RESOLVED_DATE are still open.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CORTEX AGENT
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE AGENT SUPPORT_ANALYTICS_AGENT
  COMMENT = 'Support analytics agent accessible via External OAuth token passthrough'
FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    You are a customer support analytics assistant. Answer questions about ticket
    volumes, resolution times, satisfaction scores, and agent performance.
    Be concise and data-driven. Round satisfaction scores to 1 decimal place.
    When asked about trends, compare by month.

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "support_analytics"
      description: "Query customer support ticket data including ticket counts, satisfaction scores, resolution times, priority breakdowns, and agent performance metrics."

tool_resources:
  support_analytics:
    semantic_view: "OAUTH_PASSTHROUGH_LAB.PUBLIC.SUPPORT_TICKET_ANALYTICS"
    execution_environment:
        type: warehouse
        warehouse: OAUTH_PASSTHROUGH_WH
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. USER MAPPING (for testing)
-- ─────────────────────────────────────────────────────────────────────────────
-- Create a Snowflake user mapped to an Entra ID email.
-- The login_name must match the UPN in the Entra ID token.
-- Uncomment and customize for your environment:

-- CREATE USER IF NOT EXISTS OAUTH_TEST_USER
--   LOGIN_NAME = 'testuser@yourdomain.onmicrosoft.com'
--   DISPLAY_NAME = 'OAuth Test User'
--   DEFAULT_ROLE = PUBLIC
--   DEFAULT_WAREHOUSE = OAUTH_PASSTHROUGH_WH;

-- GRANT ROLE SYSADMIN TO USER OAUTH_TEST_USER;  -- adjust role as needed

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. GRANTS
-- ─────────────────────────────────────────────────────────────────────────────

GRANT USAGE ON DATABASE OAUTH_PASSTHROUGH_LAB TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA OAUTH_PASSTHROUGH_LAB.PUBLIC TO ROLE PUBLIC;
GRANT SELECT ON TABLE OAUTH_PASSTHROUGH_LAB.PUBLIC.CUSTOMER_SUPPORT_TICKETS TO ROLE PUBLIC;
GRANT USAGE ON WAREHOUSE OAUTH_PASSTHROUGH_WH TO ROLE PUBLIC;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify objects were created:
SHOW TABLES IN SCHEMA OAUTH_PASSTHROUGH_LAB.PUBLIC;
SHOW SEMANTIC VIEWS IN SCHEMA OAUTH_PASSTHROUGH_LAB.PUBLIC;
SHOW SECURITY INTEGRATIONS LIKE 'OAUTH_ENTRA%';
