-- =============================================================================
-- Schema Mapper Agent — DDL Setup
-- Creates database, schema, stage, canonical tables, config/operational tables,
-- and reference/lookup tables.
-- =============================================================================

-- ── Database & Schema ────────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS ACME_FINANCE;
CREATE SCHEMA IF NOT EXISTS ACME_FINANCE.INGESTION;

USE SCHEMA ACME_FINANCE.INGESTION;

-- ── Internal Stage (receives CSVs from chatbot / file uploads) ───────────────
CREATE STAGE IF NOT EXISTS UPLOAD_STAGE;

-- =============================================================================
-- Canonical Tables (columns match standard financial reporting schemas)
-- =============================================================================

-- Mileage Claims — Employee mileage reimbursement submissions
CREATE TABLE IF NOT EXISTS MILEAGE_CLAIMS (
    Department              VARCHAR,
    Activity_Date           DATE,
    Employee_Name           VARCHAR,
    Employee_ID             VARCHAR,
    GL_Account              VARCHAR,
    Cost_Center             VARCHAR,
    Distance_Traveled       NUMBER(18,4),
    Distance_Unit           VARCHAR,
    Purpose                 VARCHAR,
    Vehicle_Category        VARCHAR,
    Reimbursement_Rate      NUMBER(18,4),
    Currency                VARCHAR,
    Comments                VARCHAR
);

-- Purchase Expenses — Employee purchase receipts and expense submissions
CREATE TABLE IF NOT EXISTS PURCHASE_EXPENSES (
    Department              VARCHAR,
    Transaction_Date        DATE,
    Employee_Name           VARCHAR,
    Employee_ID             VARCHAR,
    GL_Account              VARCHAR,
    Cost_Center             VARCHAR,
    Vendor_Name             VARCHAR,
    Expense_Category        VARCHAR,
    Amount                  NUMBER(18,4),
    Currency                VARCHAR,
    Payment_Method          VARCHAR,
    Receipt_Number          VARCHAR,
    Comments                VARCHAR
);

-- Vendor Invoices — Incoming vendor bills and invoices
CREATE TABLE IF NOT EXISTS VENDOR_INVOICES (
    Department              VARCHAR,
    Invoice_Date            DATE,
    Due_Date                DATE,
    Vendor_Name             VARCHAR,
    Vendor_ID               VARCHAR,
    GL_Account              VARCHAR,
    Cost_Center             VARCHAR,
    Invoice_Number          VARCHAR,
    Amount                  NUMBER(18,4),
    Currency                VARCHAR,
    Payment_Terms           VARCHAR,
    Comments                VARCHAR
);

-- =============================================================================
-- Config / Operational Tables
-- =============================================================================

-- Stores approved column-mapping configs for reuse across repeat uploads
CREATE TABLE IF NOT EXISTS MAPPING_CONFIGS (
    config_id                VARCHAR DEFAULT UUID_STRING(),
    created_at               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_column_hash       VARCHAR,
    source_column_signature  VARIANT,
    target_table             VARCHAR,
    column_map               VARIANT,
    type_coercions           VARIANT,
    value_transforms         VARIANT,
    ignored_columns          VARIANT,
    schema_version_hash      VARCHAR,
    times_used               NUMBER DEFAULT 0,
    last_used_at             TIMESTAMP_NTZ
);

-- Pending mapping proposals awaiting user approval
CREATE TABLE IF NOT EXISTS MAPPING_PROPOSALS (
    proposal_id             VARCHAR DEFAULT UUID_STRING(),
    stage_path              VARCHAR,
    target_table            VARCHAR,
    proposed_mapping        VARIANT,
    column_map              VARIANT,
    type_coercions          VARIANT,
    value_transforms        VARIANT,
    ignored_columns         VARIANT,
    confidence              NUMBER(5,4),
    model_used              VARCHAR,
    profile_summary         VARIANT,
    status                  VARCHAR DEFAULT 'PENDING',
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Execution audit log
CREATE TABLE IF NOT EXISTS RUN_HISTORY (
    run_id                  VARCHAR DEFAULT UUID_STRING(),
    config_id               VARCHAR,
    stage_path              VARCHAR,
    target_table            VARCHAR,
    rows_loaded             NUMBER,
    rows_rejected           NUMBER,
    errors                  VARCHAR,
    status                  VARCHAR DEFAULT 'success',
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- Reference / Lookup Tables
-- =============================================================================

CREATE TABLE IF NOT EXISTS REF_DEPARTMENTS (
    department_name         VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_GL_ACCOUNTS (
    gl_account_code         VARCHAR,
    gl_account_name         VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_EXPENSE_CATEGORIES (
    category_name           VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_PAYMENT_METHODS (
    method_name             VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_CURRENCIES (
    currency_code           VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_COST_CENTERS (
    cost_center_code        VARCHAR,
    cost_center_name        VARCHAR
);

CREATE TABLE IF NOT EXISTS REF_VENDORS (
    vendor_name             VARCHAR,
    vendor_id               VARCHAR
);

-- Value resolution cache (maps free-text values to canonical reference values)
CREATE TABLE IF NOT EXISTS VALUE_RESOLUTION_CACHE (
    source_values_hash      VARCHAR,
    target_column           VARCHAR,
    ref_table               VARCHAR,
    resolution_map          VARIANT,
    distinct_count          NUMBER,
    times_used              NUMBER DEFAULT 0,
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_used_at            TIMESTAMP_NTZ
);
