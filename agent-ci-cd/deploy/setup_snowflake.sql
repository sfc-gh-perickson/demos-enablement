-- =============================================================================
-- One-time Snowflake setup for Agent CI/CD Demo
-- Run this manually before first CI/CD run
-- =============================================================================

-- Create databases
CREATE DATABASE IF NOT EXISTS AGENT_CICD_DEV;
CREATE DATABASE IF NOT EXISTS AGENT_CICD_PROD;

-- Create warehouse
CREATE WAREHOUSE IF NOT EXISTS AGENT_CICD_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

-- Create role for CI/CD
CREATE ROLE IF NOT EXISTS AGENT_CICD_ROLE;

-- Grant privileges
GRANT USAGE ON WAREHOUSE AGENT_CICD_WH TO ROLE AGENT_CICD_ROLE;
GRANT ALL ON DATABASE AGENT_CICD_DEV TO ROLE AGENT_CICD_ROLE;
GRANT ALL ON DATABASE AGENT_CICD_PROD TO ROLE AGENT_CICD_ROLE;
GRANT CREATE AGENT ON SCHEMA AGENT_CICD_DEV.SEMANTIC TO ROLE AGENT_CICD_ROLE;
GRANT CREATE AGENT ON SCHEMA AGENT_CICD_PROD.SEMANTIC TO ROLE AGENT_CICD_ROLE;

-- Grant database role for AI functions
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AGENT_CICD_ROLE;

-- Grant role to your user (replace with your username)
-- GRANT ROLE AGENT_CICD_ROLE TO USER <your_username>;
