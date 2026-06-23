# PII Redaction on Snowflake

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/pii-redaction/presentations/pii-redaction.html)

An enablement module covering three approaches to PII redaction on Snowflake — from the zero-config managed function (AI_REDACT) through custom AI_COMPLETE-based extraction to pre-computed caching for sub-second response times. Includes a head-to-head comparison with a decision framework for choosing the right approach.

## Audience

Solutions engineers, data engineers, compliance teams, and security architects evaluating Snowflake for data privacy workloads involving unstructured text (document search, call transcripts, support tickets, medical records).

## Topics Covered

- The problem: PII in unstructured text at scale with latency requirements
- AI_REDACT: managed function with detect/redact modes and 12+ PII categories
- AI_COMPLETE Extract+Replace: structured JSON output with custom categories and typed labels
- The key insight: output token reduction as the primary latency lever
- Pre-computed PII cache: zero LLM calls at query time via ingestion-time extraction
- Head-to-head comparison: AI_REDACT vs AI_COMPLETE vs cached (speed, cost, flexibility)
- Decision framework: when to use each approach
- Production patterns: Tasks, Streams, Dynamic Tables for cache maintenance
- Cost analysis at scale

## Contents

| File | Description |
|------|-------------|
| `presentations/pii-redaction.html` | Slide deck (12 slides) |
| `presentations/pii-redaction-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, synthetic PII data, UDF, cache table) |
| `lab/pii-redaction-lab.ipynb` | Hands-on lab notebook (30-45 min) |

## Hands-On Lab

The lab walks participants through all three redaction approaches on the same synthetic dataset, running a fair comparison and building intuition for when to use each.

### Prerequisites

- A Snowflake account with Cortex AI features enabled
- A role with CREATE DATABASE and CREATE WAREHOUSE privileges
- Cross-region inference enabled (for AI_COMPLETE model access)

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `PII_REDACTION_DEMO` database with `REDACTION` schema
- `PII_REDACTION_WH` warehouse (MEDIUM, auto-suspend 120s)
- `DOCUMENT_CHUNKS` table — ~200 synthetic document chunks with embedded PII across 20 documents
- `REDACT_PII` Python UDF for programmatic replacement with typed labels
- `PII_ENTITY_CACHE` table (empty, populated during the lab)

### Lab Sections

1. Connect & explore synthetic data with embedded PII
2. AI_REDACT — managed redaction (detect mode, redact mode, category filtering)
3. AI_COMPLETE Extract+Replace — structured output with custom categories
4. Head-to-head comparison (same data, both approaches, timing + quality)
5. Pre-computed cache pattern (extract at ingestion, JOIN at query time)
6. Decision framework — choosing the right approach for your use case

## Key Concepts

- **AI_REDACT** — Snowflake's managed PII redaction function. Two modes: `detect` (returns PII locations as JSON) and `redact` (returns text with placeholders). Supports 12+ US PII categories. Best for standard English text within 4096 tokens.
- **AI_COMPLETE Extract+Replace** — Use any LLM to extract PII entities as structured JSON, then a Python UDF applies typed replacements. Advantages: custom categories, any language, custom labels, no token limit.
- **Pre-Computed Cache** — Extract PII at document ingestion time, store entities in a cache table. Query-time is just a JOIN + UDF — zero LLM calls, sub-second response.
- **Output Token Economics** — LLM output tokens are generated sequentially. Reducing output from 500 tokens (full text regeneration) to 5-50 tokens (JSON entities) directly reduces latency by 10-100x.

## References

- [AI_REDACT (PII Detection and Redaction)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/redact-pii)
- [AI_COMPLETE](https://docs.snowflake.com/en/sql-reference/functions/ai_complete)
- [Python UDFs](https://docs.snowflake.com/en/developer-guide/udf/python/udf-python-creating)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
