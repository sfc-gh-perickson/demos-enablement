# Evaluating Cortex Agents

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/evaluations/presentations/evaluating-cortex-agents.html)

A customer-facing enablement module covering the full evaluation lifecycle for Cortex Agents — from foundational theory through practical implementation in Snowflake.

## Audience

Technical leaders, data engineers, data scientists, and AI/ML practitioners who are building or planning to build production-grade agents.

## Topics Covered

**Theory (Part 1):**
- The trust problem — why outcome-only evaluation is insufficient
- The GPA (Goal, Plan, Action) framework from Snowflake AI Research
- Designing evaluation datasets (happy paths, edge cases, out-of-scope)
- Rubrics, metrics, and LLM-as-a-Judge
- Monitoring vs. evaluation misconceptions

**Practice (Part 2):**
- Agent versioning for safe iteration
- Running evaluations in Snowflake
- Iterating on agents using eval results
- CI/CD quality gates
- Production deployment and monitoring

## Contents

| File | Description |
|------|-------------|
| `presentations/evaluating-cortex-agents.html` | Slide deck |
| `presentations/evaluating-cortex-agents-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, tables, semantic view, search service) |
| `lab/evaluating-cortex-agents-lab.ipynb` | Hands-on lab notebook (30-45 min) |
| `rough_eval_notes.md` | Informal planning notes |

## Hands-On Lab

The lab walks participants through building and evaluating a CMO Assistant agent that combines Cortex Analyst, Cortex Search, and a custom summarization skill.

### Prerequisites

- A Snowflake account with Cortex AI features enabled
- A role with CREATE DATABASE and CREATE WAREHOUSE privileges
- Cross-region inference enabled (for LLM judge calls)
- SNOWFLAKE.CORTEX_USER database role granted to your role

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `CMO_EVAL_LAB` database
- `CMO_EVAL_WH` warehouse (XS, auto-suspend 60s)
- `CAMPAIGN_SPEND` table — 48 rows of marketing spend data (4 channels x 12 months)
- `STRATEGY_DOCS` table — 6 strategy documents for search
- `CMO_ANALYTICS` semantic view with metrics (ROI, CPC, CPA, ROAS)
- `STRATEGY_SEARCH_SVC` Cortex Search service
- `EVAL_STAGE` for YAML configs

### Lab Sections

1. Create a multi-tool CMO Assistant agent
2. Build a 12-question evaluation dataset (happy paths, multi-tool, edge cases, refusals)
3. Define metrics (answer_correctness, logical_consistency, custom tool_selection) and run evaluation
4. Inspect results, identify weaknesses, improve orchestration instructions, re-evaluate
5. Commit improved version and promote to production alias

## References

- [GPA Framework Blog Post](https://www.snowflake.com/en/blog/engineering/ai-agent-evaluation-gpa-framework/)
- [GPA Framework Paper (arXiv)](https://arxiv.org/abs/2510.08847)
- [TruLens (open-source)](https://github.com/truera/trulens)
- [Cortex Agent Evaluations Docs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst-evaluations)
