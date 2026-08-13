# Agent Observability Analysis

Mine production agent observability data to build targeted evaluation datasets. Demonstrates the flywheel: Deploy → Observe → Mine → Evaluate → Improve → Redeploy.

## What You'll Learn

1. Query explicit feedback (thumbs up/down) from `SNOWFLAKE.LOCAL.AI_OBSERVABILITY_EVENTS`
2. Detect implicit negative feedback via user rephrasing patterns
3. Classify intent trends to identify usage distribution and coverage gaps
4. Generate evaluation datasets grounded in real production weak spots

## Prerequisites

- A role with CREATE DATABASE, CREATE WAREHOUSE privileges
- Cross-region inference enabled (for CORTEX.COMPLETE and AI_EMBED)
- `SNOWFLAKE.CORTEX_USER` database role granted to your role
- `READ UNREDACTED AI OBSERVABILITY EVENTS TABLE` privilege (for full feedback text)

## Quickstart

1. Run `setup.sql` to create the `CMO_EVAL_LAB` environment
2. Open `observability-to-evals.ipynb` in Snowsight Notebooks or locally in Jupyter

## File Inventory

| File | Purpose |
|------|---------|
| `setup.sql` | Creates database, schema, warehouse, and seed data |
| `observability-to-evals.ipynb` | Main lab notebook |
| `presentations/agent-observability-analysis.html` | Companion slide deck |
| `presentations/agent-observability-analysis-speaker-notes.md` | Speaker notes |
