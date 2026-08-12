# Quick Start Guide

Get the Schema Mapper Agent running in your Snowflake account in 5 minutes.

---

## Prerequisites

- Snowflake account with **Cortex AI** enabled
- `claude-4-sonnet` model available (enable cross-region inference if needed)
- Role with `CREATE DATABASE`, `CREATE SCHEMA`, `CREATE STAGE`, `CREATE PROCEDURE`, `CREATE AGENT` privileges
- SnowSQL or a Snowflake worksheet to run SQL scripts

---

## Setup (5 steps)

### Step 1: Create database objects

```sql
-- Run in a Snowflake worksheet or via SnowSQL
SOURCE setup.sql;
```

This creates the `ACME_FINANCE.INGESTION` schema, stage, canonical tables, and operational tables.

### Step 2: Load reference data

```sql
SOURCE seed_reference_data.sql;
```

Populates reference tables with canonical departments, GL accounts, expense categories, vendors, payment methods, currencies, and cost centers.

### Step 3: Deploy all code objects

```sql
SOURCE deploy.sql;
```

Creates all UDFs, stored procedures, and the Cortex Agent. This script is idempotent — safe to re-run.

### Step 4: Deploy the semantic view

```sql
PUT 'file://semantic_view.yaml' @ACME_FINANCE.INGESTION.UPLOAD_STAGE/semantic/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
    'ACME_FINANCE.INGESTION.EXPENSE_DATA',
    (SELECT TO_VARCHAR(GET_PRESIGNED_URL(@ACME_FINANCE.INGESTION.UPLOAD_STAGE, 'semantic/semantic_view.yaml')))
);
```

### Step 5: Upload sample CSV files

```sql
-- Upload the sample files included in this package
PUT 'file://data/sample_data/mileage_claims/sample_mileage_02_messy.csv' @ACME_FINANCE.INGESTION.UPLOAD_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT 'file://data/sample_data/purchase_expenses/sample_expenses_03_chaotic.csv' @ACME_FINANCE.INGESTION.UPLOAD_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Refresh directory listing
ALTER STAGE ACME_FINANCE.INGESTION.UPLOAD_STAGE REFRESH;
```

Upload as many of the sample files as you'd like to test with. The agent discovers files automatically.

---

## Usage

### Open the Agent

1. Navigate to **Snowflake CoWork** in Snowsight
2. Select **Schema Mapper Agent**
3. Start chatting

### Sample Conversation

```
You: "Map sample_mileage_02_messy.csv"

Agent: [calls list_staged_files, confirms file exists]
Agent: [calls profile_file — shows 7 columns, 20 rows, sample values]
Agent: [calls propose_mapping — proposes mapping to MILEAGE_CLAIMS]
       "Here's the proposed mapping:
        | Source        | Target              | Operation           |
        | driver name   | EMPLOYEE_NAME       | TRIM                |
        | dist          | DISTANCE_TRAVELED   | NUMERIC_STRIP_UNITS |
        | trip date     | ACTIVITY_DATE       | TO_DATE             |
        | dept          | DEPARTMENT          | RESOLVE_ENTITY      |
        ..."
Agent: [calls preview_resolution — shows dept → canonical department table]
       "Sales & BD → Sales
        Field Ops → Field Operations
        Eng → Engineering
        ..."
Agent: "Do these resolutions look correct? Approve the mapping?"

You: "Yes, approve it"

Agent: [calls execute_mapping]
       "Loaded 20 rows into MILEAGE_CLAIMS (0 rejected)"
```

### Second Run (Cache Hit)

Run the same file again — the agent detects the cached mapping and skips the LLM call entirely:

```
You: "Map sample_mileage_02_messy.csv"
Agent: "(Cached, used 2x. Zero tokens.)" — executes immediately
```

---

## What's Included

| File | Purpose |
|------|---------|
| `setup.sql` | Database/schema/table DDL |
| `seed_reference_data.sql` | Reference data (departments, vendors, GL accounts, etc.) |
| `deploy.sql` | All UDFs, stored procedures, and the Cortex Agent |
| `semantic_view.yaml` | Semantic view for Cortex Analyst queries |
| `data/` | Sample CSV files at 3 quality tiers (clean, messy, chaotic) |
| `tests/` | SQL test suite |
| `README.md` | Full technical documentation |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `claude-4-sonnet` not available | Enable cross-region inference in account settings |
| Agent not appearing in Intelligence | Verify `CREATE AGENT` succeeded — check `SHOW AGENTS IN SCHEMA ACME_FINANCE.INGESTION` |
| COPY INTO returns 0 rows | File may have been loaded before. The SP uses `FORCE=TRUE` but check `RUN_HISTORY` table |
| Dates parsing incorrectly | The SP sets `DATE_INPUT_FORMAT='AUTO'` — ambiguous dates (01/02/2025) default to US format |

---

For full technical details, architecture diagrams, and token optimization info, see [README.md](README.md).
