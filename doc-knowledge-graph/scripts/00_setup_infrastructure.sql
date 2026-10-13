-- =============================================================================
-- Knowledge Vault Infrastructure Setup
-- =============================================================================
-- Run once to create the database, schemas, warehouse, stage, and base table.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Database
CREATE DATABASE IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO;

-- Schemas
CREATE SCHEMA IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.RAW;
CREATE SCHEMA IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.PIPELINE;
CREATE SCHEMA IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.SERVING;

-- Warehouse
CREATE WAREHOUSE IF NOT EXISTS KV_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

-- Stage for concept note markdown files
CREATE STAGE IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.RAW.NOTES_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- File format for the JSON manifest
CREATE FILE FORMAT IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.RAW.JSON_FORMAT
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = FALSE;

-- Base table: concept notes
CREATE TABLE IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.RAW.NOTES_RAW (
    note_id         VARCHAR DEFAULT UUID_STRING(),
    slug            VARCHAR NOT NULL,
    title           VARCHAR NOT NULL,
    kind            VARCHAR NOT NULL,
    body_markdown   VARCHAR,
    frontmatter_json VARIANT,
    see_also_edges  ARRAY,
    applicable_orgs ARRAY,
    updated_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (slug)
);

-- Promotion fragments table (synonyms, steering rules, verified query pairs)
CREATE TABLE IF NOT EXISTS DOC_KNOWLEDGE_GRAPH_DEMO.SERVING.PROMOTION_FRAGMENTS (
    fragment_id     VARCHAR DEFAULT UUID_STRING(),
    note_slug       VARCHAR NOT NULL,
    fragment_type   VARCHAR NOT NULL,  -- SYNONYM | STEERING_RULE | VERIFIED_QUERY_PAIR
    content_json    VARIANT NOT NULL,
    approved_at     TIMESTAMP_NTZ,
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (fragment_id)
);

-- =============================================================================
-- Cleanup (uncomment to tear down)
-- =============================================================================
-- DROP DATABASE IF EXISTS DOC_KNOWLEDGE_GRAPH_DEMO;
-- DROP WAREHOUSE IF EXISTS KV_WH;
