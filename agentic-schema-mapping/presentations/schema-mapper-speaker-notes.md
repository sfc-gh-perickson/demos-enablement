# Schema Mapper Agent — Speaker Notes

## Context

Organizations receive financial data (expense reports, mileage claims, vendor invoices) from hundreds of sources in wildly inconsistent CSV formats. Column headers vary between submitters and even between months from the same submitter. This demo shows how a Cortex Agent automates the ingestion workflow — mapping messy CSV columns to canonical financial schemas using AI-powered proposals with deterministic execution, all running entirely within Snowflake.

---

## Slide 1: Hero

**Talking Points:**

- This is a fully working solution — live in a Snowflake account, usable via Snowflake Intelligence today.
- Key stats: 0 tokens per row (LLM only proposes column mapping once), ~950 tokens for a brand new format + ~900/entity resolution column, <5s cached reload, 6 agent tools (including entity resolution preview).
- "All-in-Snowflake" means: no external services, no APIs, no ETL tools. Agent, procedures, AI_COMPLETE, COPY INTO — everything runs inside the same Snowflake account.
- Demo-able right now if they want to see it live.

---

## Slide 2: Problem Statement

**Talking Points:**

- Organizations receive CSVs monthly — expense reports, mileage logs, vendor invoices — and column headers vary wildly between departments and submitters.
- Hundreds of data sources, each with different systems. Monthly recurring uploads. 100K records at the high end.
- Multiple canonical templates means the system needs to figure out WHICH template matches, not just map columns.
- At 100K records/month, any per-row LLM approach is cost-prohibitive. The key insight is: column mapping is file-level, not row-level.
- Financial data means it has to be reliable. Can't hallucinate mappings or lose data.

---

## Slide 3: Solution Overview

**Talking Points:**

- Three-layer architecture: Agent (orchestration + chat) → AI_COMPLETE (one-time mapping proposal) → Deterministic SP (at-scale execution).
- The key insight: separate the "thinking" (which columns map where?) from the "doing" (COPY INTO 100K rows). The LLM thinks once; the SP does repeatedly.
- AI_COMPLETE is called exactly once per NEW file format — inside propose_mapping on cache miss. Everything else is deterministic SQL.
- The agent NEVER writes SQL directly. It calls tools, tools return structured data, agent presents to user.

---

## Slide 4: Architecture

**Talking Points:**

- Show the data flow: Agent → 6 tools → underlying SPs/UDFs → COPY INTO.
- GET_TARGET_SCHEMAS reads INFORMATION_SCHEMA live, so adding new templates auto-extends the agent's knowledge without redeployment.
- MAPPING_CONFIGS is the cache layer at the center — fed by AI_COMPLETE on miss, queried on every proposal.
- The stage is the entry point for data. Directory table enables file listing without scanning.
- Emphasize: the only arrow that touches AI_COMPLETE is from PROPOSE_MAPPING, and only on cache miss.

---

## Slide 5: Stored Procedures & UDFs

**Talking Points:**

- Walk through the table top-to-bottom. Note the separation between agent-facing tools (LIST_STAGED_FILES, PROFILE_FILE, PROPOSE_MAPPING, EXECUTE_MAPPING, GET_TARGET_SCHEMAS, PREVIEW_RESOLUTION) and internal SPs (SP_PROFILE_STAGED_FILE, SP_BUILD_AND_EXECUTE_COPY_INTO, SP_RESOLVE_COLUMN_VALUES).
- SP_PROFILE_STAGED_FILE does the heavy lifting: INFER_SCHEMA for type detection, then samples 20 rows and computes per-column stats. Zero tokens — pure SQL.
- PROPOSE_MAPPING is the only object that MAY call AI_COMPLETE. Cache check is first.
- SP_BUILD_AND_EXECUTE_COPY_INTO is the deterministic core. Receives structured JSON, produces exact COPY INTO. No ambiguity, no LLM.

---

## Slide 6: Workflow — Discovery & Profiling

**Talking Points:**

- Step 1 is trivial — just listing files. But it's important for UX: user says "I want to map an expense file" and agent shows what's available.
- Step 2 (profiling) is the most important zero-token step. INFER_SCHEMA detects types without loading. Sample rows give the agent (and the LLM, if cache miss) real data to reason about.
- The profile includes 5 sample values per column. This is what lets the LLM distinguish "Amt" (an amount with currency symbols) from "Dist" (a distance with units).
- Step 3: emphasize the cache check happens BEFORE any LLM call. SHA256 of sorted lowercase column names. If the same columns appeared before (any filename, any order), it's a hit.

---

## Slide 7: Workflow — Approval & Execution

**Talking Points:**

- Step 4 (approval) is the critical human-in-the-loop gate. Enforced in the agent's system prompt — it cannot skip to execution without explicit user confirmation.
- The agent presents the mapping as a structured table: Source → Target → Operation. Clear enough for a non-technical user to validate.
- Step 5 is fully deterministic. Walk through the generated COPY INTO: positional references ($1, $2, $3...), transform expressions from the operations enum, target table, file format options.
- On success: mapping saved to MAPPING_CONFIGS. On failure: nothing saved, error reported. The cache only contains proven-good mappings.
- FORCE=TRUE allows re-running the same file (useful during development and for monthly re-uploads).

---

## Slide 8: Operations Enum

**Talking Points:**

- These are the transform primitives. The LLM picks which operation applies to each column; the SP generates the exact SQL. Adding a new operation = one CASE branch in the SP.
- NUMERIC_STRIP_UNITS is the workhorse: handles "$1,234", "~500", currency symbols, commas, tildes all stripped to a clean number. The tilde handling was added after seeing real data with "~152" meaning "approximately 152".
- TO_DATE_START/END handle date ranges: "Jan 1, 2025 – Mar 31, 2025" or "2025-01-01 to 2025-03-31" — REGEXP_REPLACE normalizes all separators to ' to ', SPLIT_PART extracts each half.
- Key point: one source column CAN map to multiple targets with different operations.
- RESOLVE_ENTITY handles semantic matching of free-text values to canonical reference values.

---

## Slide 9: Benchmark Results

**Talking Points:**

- These are REAL benchmarked numbers from running sample files through the pipeline cold (no cache) then warm (cached).
- Key headline: ~9.6x overall speedup on cached path.
- Token estimates: ~950 tokens per mapping call (measured from prompt/response char lengths). ~900 tokens per entity resolution column.
- The comparison: per-row LLM at 100K rows = millions of tokens/month. We pay ~950-1,850 once, then 0 forever.
- Cross-file reuse: files with the same column signature automatically share cache — different filenames, different data, same columns = instant.
- Entity resolution timing: ~29s cold → 0.2s cached. This is the most expensive single step, but with caching it becomes negligible.

---

## Slide 10: Mapping Cache Deep Dive

**Talking Points:**

- The hash is SHA256 of sorted, lowercased column names joined by pipe. Same columns in different order = same hash. Different filename = same hash.
- Walk through the lookup: compute hash → query MAPPING_CONFIGS → if hit, return stored JSON + increment times_used → if miss, proceed to AI_COMPLETE.
- Real-world scenario: Finance uploads "expenses_jan_2026.csv" and "expenses_feb_2026.csv" — same columns, different filenames. February gets instant cache hit.
- Cache is only saved AFTER successful execution of an approved mapping. Failed loads don't pollute the cache.
- times_used counter gives visibility into which mappings are most valuable / frequently reused.

---

## Slide 11: Date Handling Deep Dive

**Talking Points:**

- Real data has mixed date formats WITHIN A SINGLE COLUMN: "2025-01-15", "Jan 21, 2025", "02/14/2025" all in the same CSV.
- COPY INTO with explicit format strings fails on mixed formats. `DATE_INPUT_FORMAT = 'AUTO'` at session level lets Snowflake auto-detect per row.
- Date ranges are the second challenge: "05/09/2025 to 05/13/2025" needs to split into start and end dates.
- Known limitation: DD/MM/YYYY vs MM/DD/YYYY is ambiguous for dates like 01/02/2025. AUTO uses US-format bias. ON_ERROR=CONTINUE catches truly unparseable values.

---

## Slide 12: Requirements Solved

**Talking Points:**

- "100K records without per-row LLM" — one AI_COMPLETE call (~950 tokens) then deterministic COPY INTO for all rows.
- "Shared memory" — don't want submitters re-answering the same questions each month. MAPPING_CONFIGS solves this completely.
- "Template matching" — GET_TARGET_SCHEMAS injects live schema into the AI_COMPLETE prompt. The LLM sees all available templates and picks the best match.
- "Distinct-value entity resolution" — resolves ~25 vendor descriptions to canonical vendor names via LLM + caches. Applied via CASE WHEN in COPY INTO.
- "Speed/cost at scale" — cached path is under 5 seconds wall-clock. No warm-up, no model loading, just a table lookup + COPY INTO.

---

## Slide 13: Gaps & Future

**Talking Points:**

- Remaining gaps are smaller than they look.
- Referential integrity validation (valid GL account → valid cost center combinations) is a post-load SQL check — doesn't require LLM.
- Additional templates: only 3 implemented (mileage, purchases, invoices). Adding more is mechanical (DDL + reference data).
- Multi-tenancy: table column + session variable filter. Low engineering effort.
- Evaluation harness: use Cortex Agent Evaluations to assert N test files consistently produce correct mappings across model updates.

---

## Slide 14: Next Steps

**Talking Points:**

- Cortex Search for Fuzzy Matching: currently entity resolution uses LLM calls (~29s cold). Cortex Search on reference tables would give sub-second fuzzy matching without a cache hit.
- Post-load Validation: query that checks referential integrity between GL accounts, cost centers, and departments.
- Multi-tenant config: add TENANT_ID to MAPPING_CONFIGS and VALUE_RESOLUTION_CACHE, filter by tenant.
- Evaluation Harness — use Cortex Agent Evaluations with known-correct test files.
- Additional templates: GET_TARGET_SCHEMAS auto-discovers new tables. Adding a template is DDL + reference data. No agent or SP changes.

---

## Slide 15: Demo Flow

**Talking Points:**

- Open Snowflake Intelligence → select Schema Mapper Agent → say "Map sample_mileage_02_messy.csv".
- Watch the agent: calls list_staged_files (confirms file exists) → calls profile_file (shows column metadata) → calls propose_mapping (AI_COMPLETE or cache hit) → presents mapping table with unmapped columns → calls preview_resolution for entity columns → shows resolution table → wait for approval.
- Say "Yes, approve it". Watch execute_mapping fire. See "Loaded 20 rows into MILEAGE_CLAIMS (0 rejected)". Agent shows sample of loaded data.
- BONUS: immediately run the same file again. Watch the cache hit — no AI_COMPLETE call, instant mapping proposal, <5s total.
- If time allows: show a chaotic file with mixed date formats and currency-prefixed numbers to demonstrate NUMERIC_STRIP_UNITS and TO_DATE in action.

---

## Internal Engineering Notes

### Model Selection

- **Claude-4-sonnet** is required for reliable JSON output from AI_COMPLETE. Tested with other models — they hallucinated column names that didn't exist in the source file and inconsistently followed the JSON schema.
- The agent itself runs on whatever model Snowflake Intelligence uses for agents.

### Agent Configuration Gotchas

- **Tool type must be "generic"** in the agent specification. Not "custom_tool" or any other value.
- **Procedures need `"type": "procedure"` in tool_resources.** Without this, the agent tries to call it as a UDF and fails silently.
- Adding explicit formatting examples in the system prompt helps the agent present mappings as tables vs raw JSON.

### Date Parsing Workaround

- COPY INTO with TRY_TO_DATE failed on mixed date formats within a single column UNLESS `DATE_INPUT_FORMAT = 'AUTO'` was set at the session level.
- Set via `ALTER SESSION SET DATE_INPUT_FORMAT = 'AUTO'` at the start of SP_BUILD_AND_EXECUTE_COPY_INTO.
- Ambiguous dates (01/02/2025 — Jan 2 or Feb 1?) use Snowflake's US-format bias with AUTO.

### COPY INTO Behavior

- `ON_ERROR = CONTINUE` skips rows with type conversion errors rather than failing the entire load.
- `FORCE = TRUE` allows re-loading the same file.

### Token Counts (Measured)

- Mapping proposal: ~950 tokens total per call
- Entity resolution: ~900 tokens total per call
- 6 sample files cold pass: ~8,350 total tokens. Warm pass: 0 tokens (100% cached).

---

## Doc Links

- [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent)
- [AI_COMPLETE](https://docs.snowflake.com/en/sql-reference/functions/ai_complete-snowflake-cortex)
- [COPY INTO](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table)
- [INFER_SCHEMA](https://docs.snowflake.com/en/sql-reference/functions/infer_schema)
- [Semantic Views](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst/semantic-view)
- [Cortex Agent Evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent/evaluations)
