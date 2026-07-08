-- =============================================================================
-- Label Studio on SPCS Lab: Setup Script
-- =============================================================================
-- Run this script once before starting the lab notebooks.
-- It creates all prerequisite objects: database, schemas, warehouse, image 
-- repository, Snowflake Postgres instance, compute pool, stages, and service.
--
-- Prerequisites:
--   - A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE COMPUTE POOL,
--     CREATE POSTGRES INSTANCE privileges
--   - ACCOUNTADMIN (or delegated) for external access integrations
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE AND SCHEMA
-- ─────────────────────────────────────────────────────────────────────────────
-- Central database for all Label Studio on SPCS lab objects.

CREATE DATABASE IF NOT EXISTS LABEL_STUDIO_SPCS;
USE DATABASE LABEL_STUDIO_SPCS;

CREATE SCHEMA IF NOT EXISTS APP
    COMMENT = 'Schema for Label Studio application objects (service, stages, specs)';
USE SCHEMA APP;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WAREHOUSE
-- ─────────────────────────────────────────────────────────────────────────────
-- XS warehouse for running lab queries and loading data.

CREATE WAREHOUSE IF NOT EXISTS LABEL_STUDIO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for Label Studio on SPCS lab';

USE WAREHOUSE LABEL_STUDIO_WH;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. IMAGE REPOSITORY
-- ─────────────────────────────────────────────────────────────────────────────
-- Stores the Label Studio container image pushed from Docker.

CREATE IMAGE REPOSITORY IF NOT EXISTS LABEL_STUDIO_REPO
    COMMENT = 'Container image repository for Label Studio';

-- Show the repository URL (needed for docker tag & push)
SHOW IMAGE REPOSITORIES IN SCHEMA;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. NETWORK RULES AND POLICY FOR POSTGRES
-- ─────────────────────────────────────────────────────────────────────────────
-- Network policy to allow inbound connections to the Postgres instance.
-- NOTE: 0.0.0.0/0 allows all IPs — acceptable for lab environments only.
--       In production, restrict to specific CIDR ranges.

CREATE OR REPLACE NETWORK RULE PG_INGRESS_ALL
    MODE = POSTGRES_INGRESS
    TYPE = IPV4
    VALUE_LIST = ('0.0.0.0/0')
    COMMENT = 'Allow all inbound Postgres connections (LAB ONLY — restrict in production)';

CREATE OR REPLACE NETWORK POLICY LABEL_STUDIO_PG_POLICY
    ALLOWED_NETWORK_RULE_LIST = ('PG_INGRESS_ALL')
    COMMENT = 'Network policy for Label Studio Postgres instance';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. SNOWFLAKE POSTGRES INSTANCE
-- ─────────────────────────────────────────────────────────────────────────────
-- Backend database for Label Studio. Stores projects, annotations, users, etc.

CREATE POSTGRES INSTANCE IF NOT EXISTS LABEL_STUDIO_PG
    COMPUTE_FAMILY = 'BURST_S'
    STORAGE_SIZE_GB = 10
    AUTHENTICATION_AUTHORITY = POSTGRES
    POSTGRES_VERSION = 17
    NETWORK_POLICY = 'LABEL_STUDIO_PG_POLICY'
    COMMENT = 'Postgres backend for Label Studio on SPCS';

-- ╔═══════════════════════════════════════════════════════════════════════════╗
-- ║  IMPORTANT: Save the credentials from the output above!                  ║
-- ║                                                                          ║
-- ║  The CREATE POSTGRES INSTANCE command returns:                           ║
-- ║    - Host: e.g. abc123.snowflakecomputing.app                           ║
-- ║    - Port: 5432                                                          ║
-- ║    - Username: application                                               ║
-- ║    - Password: (auto-generated)                                          ║
-- ║                                                                          ║
-- ║  You will need the HOST and PASSWORD when configuring the service spec.  ║
-- ║  Copy them now — the password cannot be retrieved again without reset.   ║
-- ╚═══════════════════════════════════════════════════════════════════════════╝

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. INTERNAL STAGES
-- ─────────────────────────────────────────────────────────────────────────────
-- SPEC_STAGE: holds the YAML service specification file
-- DATA_STAGE: holds labeling data files accessible to Label Studio

CREATE STAGE IF NOT EXISTS SPEC_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Label Studio SPCS service specification YAML';

CREATE STAGE IF NOT EXISTS DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for labeling data files accessible to Label Studio';

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. COMPUTE POOL
-- ─────────────────────────────────────────────────────────────────────────────
-- Compute pool to run the Label Studio container service.

CREATE COMPUTE POOL IF NOT EXISTS LABEL_STUDIO_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = CPU_X64_S
    AUTO_SUSPEND_SECS = 300
    AUTO_RESUME = TRUE
    COMMENT = 'Compute pool for Label Studio SPCS service';

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. EXTERNAL ACCESS INTEGRATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Allows the Label Studio service to reach PyPI for any runtime dependencies.

CREATE OR REPLACE NETWORK RULE LABEL_STUDIO_EGRESS_RULE
        MODE = EGRESS
        TYPE = HOST_PORT
        VALUE_LIST = (
            'pypi.org',
            'files.pythonhosted.org',
            'em7kgv3ijze4zlnw26unn6quvq.sfsenorthamerica-perickson-aws1.us-east-2.aws.postgres.snowflake.app:5432'
        );
    -- Single EAI referencing the one rule
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION LABEL_STUDIO_EAI
    ALLOWED_NETWORK_RULES = (LABEL_STUDIO_EGRESS_RULE)
    ENABLED = TRUE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8b. EXTERNAL ACCESS FOR POSTGRES QUERIES
-- ─────────────────────────────────────────────────────────────────────────────
-- Allows Snowflake stored procedures to query the Postgres instance directly.
-- Replace <POSTGRES_HOST> with the actual host from CREATE POSTGRES INSTANCE output.

CREATE OR REPLACE NETWORK RULE PG_EGRESS_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('<POSTGRES_HOST>')
    COMMENT = 'Egress rule for connecting to Snowflake Postgres instance (replace <POSTGRES_HOST>, do NOT append port)';

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION PG_ACCESS_EAI
    ALLOWED_NETWORK_RULES = (PG_EGRESS_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (PG_CREDENTIALS)
    ENABLED = TRUE
    COMMENT = 'External access integration for querying Label Studio Postgres backend';

-- Secret to store Postgres connection credentials.
-- Update the values after running CREATE POSTGRES INSTANCE in section 5.
CREATE OR REPLACE SECRET PG_CREDENTIALS
    TYPE = GENERIC_STRING
    SECRET_STRING = '{"host":"<POSTGRES_HOST>","port":"5432","dbname":"postgres","user":"application","password":"<POSTGRES_PASSWORD>"}'
    COMMENT = 'Postgres connection credentials for Label Studio backend (update after instance creation)';

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. SAMPLE DATA AND EXPORT TABLE
-- ─────────────────────────────────────────────────────────────────────────────
-- Sample text records for sentiment analysis labeling in Label Studio.

CREATE TABLE IF NOT EXISTS LABELING_TASKS (
    TASK_ID NUMBER,
    TEXT_CONTENT VARCHAR,
    CATEGORY VARCHAR
);

INSERT INTO LABELING_TASKS (TASK_ID, TEXT_CONTENT, CATEGORY) VALUES
    (1, 'Absolutely love this product! It exceeded all my expectations and the quality is outstanding.', 'product_review'),
    (2, 'Terrible experience. The item arrived broken and customer service was unhelpful.', 'product_review'),
    (3, 'The package arrived on time. It works as described in the listing.', 'product_review'),
    (4, 'Best purchase I have made this year! Would recommend to everyone I know.', 'product_review'),
    (5, 'Very disappointed with the build quality. Feels cheap and flimsy for the price.', 'product_review'),
    (6, 'It is fine. Nothing special but it gets the job done without any issues.', 'product_review'),
    (7, 'The customer support team went above and beyond to resolve my issue quickly.', 'customer_feedback'),
    (8, 'Waited 3 weeks for delivery and received the wrong item. Extremely frustrated.', 'customer_feedback'),
    (9, 'Ordered the standard size. It fits as expected and matches the color shown online.', 'customer_feedback'),
    (10, 'This is hands down the best value for money in its category. Five stars!', 'product_review'),
    (11, 'The software crashes constantly and the latest update made it even worse.', 'product_review'),
    (12, 'Received my order yesterday. The packaging was adequate and item was intact.', 'customer_feedback'),
    (13, 'Incredible improvement over the previous version — faster, sleeker, and more intuitive.', 'product_review'),
    (14, 'Do not buy this. It stopped working after two days and the warranty process is a nightmare.', 'product_review'),
    (15, 'The product dimensions match what was listed on the website.', 'product_review'),
    (16, 'My family loves using this every weekend. It has become a household staple for us.', 'customer_feedback'),
    (17, 'Refund process took over a month. No communication from the seller during that time.', 'customer_feedback'),
    (18, 'Placed the order on Monday and it arrived on Wednesday via standard shipping.', 'customer_feedback');

-- Table for storing exported annotations from Label Studio
CREATE TABLE IF NOT EXISTS LABELED_DATA (
    TASK_ID NUMBER        COMMENT 'Label Studio task ID',
    TEXT_CONTENT VARCHAR  COMMENT 'Original text that was labeled',
    LABEL VARCHAR         COMMENT 'Annotation label assigned by annotator',
    ANNOTATOR VARCHAR     COMMENT 'Email of the annotator',
    ANNOTATED_AT TIMESTAMP_NTZ COMMENT 'Timestamp when annotation was created'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. VERIFICATION
-- ─────────────────────────────────────────────────────────────────────────────
-- Verify that all objects were created successfully.

SHOW SCHEMAS IN DATABASE LABEL_STUDIO_SPCS;
SHOW STAGES IN SCHEMA LABEL_STUDIO_SPCS.APP;
SHOW IMAGE REPOSITORIES IN SCHEMA LABEL_STUDIO_SPCS.APP;
SHOW COMPUTE POOLS LIKE 'LABEL_STUDIO_POOL';
DESCRIBE POSTGRES INSTANCE LABEL_STUDIO_PG;

-- NOTE: The service is NOT created by this setup script.
-- The CREATE SERVICE command is run in the lab notebook after:
--   1. Building and pushing the Docker image to LABEL_STUDIO_REPO
--   2. Updating label-studio-spec.yaml with Postgres credentials
--   3. Uploading the spec to @SPEC_STAGE
--
-- Example (run in lab notebook):
--   CREATE SERVICE LABEL_STUDIO_SERVICE
--     IN COMPUTE POOL LABEL_STUDIO_POOL
--     FROM @SPEC_STAGE
--     SPECIFICATION_FILE = 'label-studio-spec.yaml'
--     EXTERNAL_ACCESS_INTEGRATIONS = (LABEL_STUDIO_EAI);

-- SHOW SERVICES IN SCHEMA LABEL_STUDIO_SPCS.APP;
-- SHOW ENDPOINTS IN SERVICE LABEL_STUDIO_SERVICE;

-- ─────────────────────────────────────────────────────────────────────────────
-- SETUP COMPLETE
-- ─────────────────────────────────────────────────────────────────────────────
-- Expected output:
--   - Database: LABEL_STUDIO_SPCS
--   - Schema: APP
--   - Warehouse: LABEL_STUDIO_WH (XSMALL, auto-suspend 60s)
--   - Image Repository: LABEL_STUDIO_REPO
--   - Postgres Instance: LABEL_STUDIO_PG (BURST_S, 10GB, Postgres 17)
--   - Stages: SPEC_STAGE, DATA_STAGE
--   - Compute Pool: LABEL_STUDIO_POOL (CPU_X64_S, 1 node)
--   - External Access Integration: LABEL_STUDIO_EAI (PyPI egress)
--   - Table: LABELING_TASKS (18 sample records for sentiment analysis)
