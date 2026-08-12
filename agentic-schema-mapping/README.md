# Agentic Schema Mapping

An all-in-Snowflake pipeline that maps messy CSV data into canonical financial table schemas. A **Cortex Agent** orchestrates the workflow via Snowflake CoWork chat, using custom tools (stored procedures/UDFs) for profiling, AI-powered mapping proposals, and deterministic COPY INTO execution.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  CORTEX AGENT (Snowflake CoWork)                                      │
│  Orchestrates the workflow, presents results, gets user approval             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────────┐   ┌─────────────┐ │
│  │ list_staged │   │ profile_file │   │propose_mapping│   │execute_     │ │
│  │ _files()    │   │ (filename)   │   │(profile_text) │   │mapping(json)│ │
│  └──────┬──────┘   └──────┬───────┘   └───────┬───────┘   └──────┬──────┘ │
│         │                  │                   │                   │        │
└─────────┼──────────────────┼───────────────────┼───────────────────┼────────┘
          │                  │                   │                   │
          ▼                  ▼                   ▼                   ▼
┌─────────────┐   ┌──────────────────┐   ┌───────────────┐   ┌─────────────┐
│  DIRECTORY  │   │SP_PROFILE_STAGED │   │ AI_COMPLETE   │   │SP_BUILD_AND │
│  @UPLOAD_   │   │_FILE             │   │(claude-4-son) │   │EXECUTE_COPY │
│  STAGE      │   │• INFER_SCHEMA    │   │+ schema from  │   │_INTO        │
│             │   │• Sample rows     │   │GET_TARGET_    │   │• Dynamic SQL│
│             │   │• Column stats    │   │SCHEMAS()      │   │• COPY INTO  │
└─────────────┘   └──────────────────┘   └───────┬───────┘   └──────┬──────┘
                                                  │                   │
                                         ┌────────┴────────┐         │
                                         │ MAPPING_CONFIGS │◀────────┘
                                         │ (cache layer)   │  saves on success
                                         └─────────────────┘
```

---

## Agent Workflow

The Cortex Agent (`ACME_FINANCE.INGESTION.SCHEMA_MAPPER_AGENT`) follows this exact workflow:

### Step 1: File Discovery
```
User: "I want to map an expense file"
Agent → calls list_staged_files()
Agent: "Here are the available files: sample_expenses_03_chaotic.csv, ..."
```

### Step 2: Profiling
```
Agent → calls profile_file('sample_expenses_03_chaotic.csv')
Agent: "Here's what I found:
  - 11 columns, 31 rows
  - Person (TEXT): 20 distinct employees
  - Amt (TEXT): amounts with mixed formats ($142.67, ~2400, 89.45)
  - Dt (TEXT): mixed date formats (YYYY-MM-DD, MM/DD/YYYY, Mon DD YYYY)
  ..."
```

### Step 3: Mapping Proposal
```
Agent → calls propose_mapping(profile_text)
       └─ internally: checks MAPPING_CONFIGS cache first (SHA256 hash of sorted column names)
       └─ if cache miss: calls AI_COMPLETE('claude-4-sonnet') with schema + profile
Agent: "Proposed mapping to PURCHASE_EXPENSES:
  | Source      | Target           | Operation          |
  |-------------|------------------|--------------------|
  | Person      | EMPLOYEE_NAME    | TRIM               |
  | Place/Thing | VENDOR_NAME      | RESOLVE_ENTITY     |
  | Amt         | AMOUNT           | NUMERIC_STRIP_UNITS|
  | Dt          | TRANSACTION_DATE | TO_DATE            |
  | Grp         | DEPARTMENT       | RESOLVE_ENTITY     |
  Ignored: Approved?, Misc
  
  Approve this mapping?"
```

### Step 4: Ambiguity Check (CRITICAL — never skipped)
```
Agent checks for:
  a) MISSING CURRENCY: If amounts are plain numbers without currency symbol,
     ASK the user what currency the data is in.
  b) ENTITY RESOLUTION: For EVERY RESOLVE_ENTITY column, call preview_resolution.
     Show the FULL resolution table to the user.
  c) UNMATCHED VALUES: If any values show NO MATCH, ask the user what they map to.
  d) UNMAPPED TARGET COLUMNS: List which canonical table columns will be LEFT EMPTY.

Agent → calls preview_resolution('sample_expenses_03_chaotic.csv',
          'Place/Thing', 2, 'REF_VENDORS', 'VENDOR_NAME')
Agent: "Here's how vendor descriptions resolve to canonical vendors:
  | Source Value    | Resolved To            |
  |----------------|------------------------|
  | gas - shell    | Shell Gas Station      |
  | AWS            | Amazon Web Services    |
  | lowes          | Lowe's                 |
  ...
  20 matched, 0 unmatched. Do these look correct?"
```

### Step 5: User Approval (NEVER SKIPPED)
```
User: "Yes, approve it"
```

### Step 6: Execution
```
Agent → calls execute_mapping(mapping_json, filename)
       └─ internally: SP_BUILD_AND_EXECUTE_COPY_INTO builds deterministic COPY INTO
       └─ RESOLVE_ENTITY columns generate CASE WHEN statements from resolution map
       └─ saves approved mapping to MAPPING_CONFIGS for future reuse
Agent: "Loaded 31 rows into PURCHASE_EXPENSES (0 rejected)"
```

---

## Components

### Cortex Agent

**Object:** `ACME_FINANCE.INGESTION.SCHEMA_MAPPER_AGENT`

Created via `CREATE AGENT ... FROM SPECIFICATION`. Uses Snowflake CoWork as the chat UI. Has 6 custom tools (type `"generic"`) backed by UDFs and stored procedures.

| Tool | Type | Identifier | Purpose |
|------|------|-----------|---------|
| `list_staged_files` | UDF | `LIST_STAGED_FILES()` | Lists CSVs on `@UPLOAD_STAGE` via directory table |
| `profile_file` | Procedure | `PROFILE_FILE(VARCHAR)` | Profiles a CSV: columns, types, samples, null rates |
| `get_target_schemas` | UDF | `GET_TARGET_SCHEMAS()` | Returns canonical table schemas from INFORMATION_SCHEMA |
| `propose_mapping` | Procedure | `PROPOSE_MAPPING(VARCHAR)` | Cache check + AI_COMPLETE mapping proposal |
| `preview_resolution` | Procedure | `PREVIEW_RESOLUTION(...)` | Shows entity resolution preview for RESOLVE_ENTITY columns |
| `execute_mapping` | Procedure | `EXECUTE_MAPPING(VARCHAR, VARCHAR)` | Builds and runs COPY INTO, saves config |

### Mapping Cache (`MAPPING_CONFIGS`)

Approved mappings are cached by a **SHA256 hash of sorted lowercase column names**. When a new file has the same columns (regardless of filename), the cache hits and returns instantly — zero LLM tokens.

### Entity Resolution (`SP_RESOLVE_COLUMN_VALUES`)

For columns mapped with `RESOLVE_ENTITY` operation (e.g., vendor descriptions → canonical vendor names):

1. Extract distinct non-null values from the source column
2. Check `VALUE_RESOLUTION_CACHE` (keyed by SHA2 of sorted lowercase values + target column)
3. On cache miss: fetch canonical values from reference table, call `AI_RESOLVE_VALUES` UDF
4. LLM returns `{mappings: [{source_value, canonical_value}, ...]}` via structured output
5. During COPY INTO execution, generate a `CASE WHEN` from the resolution map

**Cost model:** LLM calls are proportional to distinct values (~25 vendors), NOT row count (~100K rows). Cache means subsequent files with the same values cost 0 tokens.

### Deterministic COPY INTO Builder (`SP_BUILD_AND_EXECUTE_COPY_INTO`)

**No LLM writes SQL.** The stored procedure deterministically constructs COPY INTO from the operations enum:

| Operation | Generated SQL Expression |
|-----------|------------------------|
| `TRIM` | `NULLIF(TRIM($N), '')` |
| `NUMERIC_STRIP_UNITS` | `TRY_TO_NUMBER(REGEXP_REPLACE(REPLACE($N, '~', ''), '[^0-9.]', ''))` |
| `TO_DATE` | `TRY_TO_DATE(TRIM($N))` |
| `TO_DATE_START` | `TRY_TO_DATE(TRIM(SPLIT_PART(REGEXP_REPLACE($N, ...), ' to ', 1)))` |
| `TO_DATE_END` | `COALESCE(TRY_TO_DATE(part2), TRY_TO_DATE(part1))` |
| `TO_NUMBER` | `TRY_TO_NUMBER($N)` |
| `DIRECT` | `$N` (pass-through) |
| `RESOLVE_ENTITY` | `CASE WHEN TRIM($N) = 'src' THEN 'canonical' ... END` |

---

## Semantic View

**Object:** `ACME_FINANCE.INGESTION.EXPENSE_DATA`

Exposes the 3 canonical tables as a unified expense data model for Cortex Analyst queries.

- **Dimensions:** Department, Employee_Name, Vendor_Name, Expense_Category, GL_Account, Cost_Center
- **Time dimensions:** Activity_Date, Transaction_Date, Invoice_Date, Due_Date
- **Measures:** Distance_Traveled (sum), Amount (sum), Reimbursement_Rate (avg)

---

## Deployment

### Prerequisites

- Snowflake account with Cortex AI enabled (`claude-4-sonnet` model available)
- Role with CREATE DATABASE, CREATE SCHEMA, CREATE STAGE, CREATE PROCEDURE, CREATE AGENT privileges
- Cross-region inference enabled if Claude isn't available in your region

### Quick Start (Full Setup)

Run these in order in a Snowflake worksheet:

```sql
-- 1. Create database, schema, stage, canonical tables, config tables, reference tables
SOURCE setup.sql;

-- 2. Seed reference data (departments, GL accounts, vendors, expense categories, etc.)
SOURCE seed_reference_data.sql;

-- 3. Deploy all UDFs, stored procedures, and the Cortex Agent
SOURCE deploy.sql;
```

That's it. The agent is now live.

### Upload Data & Start Using

```sql
-- Upload CSV files to the stage
PUT 'file:///path/to/expense_data.csv' @ACME_FINANCE.INGESTION.UPLOAD_STAGE;
ALTER STAGE ACME_FINANCE.INGESTION.UPLOAD_STAGE REFRESH;
```

Then open **Snowflake CoWork** in Snowsight, select **Schema Mapper Agent**, and say:
> "Map expense_data.csv"

### Re-deployment

`deploy.sql` is fully idempotent (`CREATE OR REPLACE` for all objects). Re-run it any time to update agent logic without affecting stored configs or loaded data.

---

## Token Optimization

| Layer | Technique | Tokens |
|-------|-----------|--------|
| Profile | Pure SQL (INFER_SCHEMA + sample rows) | 0 |
| Cache hit | SHA256 hash lookup in MAPPING_CONFIGS | 0 |
| Cache miss — mapping | AI_COMPLETE with schema + profile | ~950 |
| Cache miss — entity resolution | AI_RESOLVE_VALUES per distinct-value set | ~900/column |
| Entity resolution (cache hit) | SHA256 lookup in VALUE_RESOLUTION_CACHE | 0 |
| Execution | Deterministic SQL builder (no LLM) | 0 |
| Repeat uploads | Same column signature → cache hit | 0 |

First mapping of a new format: **~950 tokens** + **~900/column** needing entity resolution. All subsequent uploads with the same columns: **0 tokens**.

---

## Canonical Table Schemas

| Table | Columns |
|-------|---------|
| `MILEAGE_CLAIMS` | Department, Activity_Date, Employee_Name, Employee_ID, GL_Account, Cost_Center, Distance_Traveled, Distance_Unit, Purpose, Vehicle_Category, Reimbursement_Rate, Currency, Comments |
| `PURCHASE_EXPENSES` | Department, Transaction_Date, Employee_Name, Employee_ID, GL_Account, Cost_Center, Vendor_Name, Expense_Category, Amount, Currency, Payment_Method, Receipt_Number, Comments |
| `VENDOR_INVOICES` | Department, Invoice_Date, Due_Date, Vendor_Name, Vendor_ID, GL_Account, Cost_Center, Invoice_Number, Amount, Currency, Payment_Terms, Comments |

---

## File Index

| File | Purpose |
|------|---------|
| `deploy.sql` | **Single consolidated deployment script** — all UDFs, SPs, agent, stage config |
| `setup.sql` | DDL for all database objects (tables, stage, schema) |
| `seed_reference_data.sql` | Reference data INSERT statements (departments, vendors, GL accounts, etc.) |
| `semantic_view.yaml` | Semantic view definition for Cortex Analyst |
| `tests/test_column_mapping.sql` | Infrastructure validation test cases |
| `data/` | Sample data at 3 quality tiers (clean, messy, chaotic) |

---

## Extending to New Financial Data Types

1. Add canonical table DDL to `setup.sql` (e.g., `JOURNAL_ENTRIES`, `PAYROLL_RECORDS`)
2. Add reference data to `seed_reference_data.sql`
3. `GET_TARGET_SCHEMAS()` auto-discovers new tables from INFORMATION_SCHEMA
4. `PROPOSE_MAPPING` auto-includes new tables in AI_COMPLETE prompt
5. No agent changes needed — it discovers new schemas via tools

---

## Known Limitations

- **File upload:** Snowflake CoWork attachments don't auto-stage files. Users must `PUT` files to `@UPLOAD_STAGE` first (via Snowsight, SnowSQL, or integrated upload flow).
- **Date ambiguity:** DD/MM/YYYY vs MM/DD/YYYY is ambiguous for dates like `01/02/2025`. `DATE_INPUT_FORMAT = 'AUTO'` uses Snowflake's heuristic (US-format bias).
- **Entity resolution limited to 30 distinct values:** `SP_RESOLVE_COLUMN_VALUES` sends up to 30 distinct values to the LLM at a time.
- **3 templates in scope:** Only mileage, purchases, and invoices. Additional financial data types need DDL + reference data.
