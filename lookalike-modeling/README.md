# Lookalike Modeling with Cortex Agent Skills

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/lookalike-modeling/presentations/lookalike-modeling.html)

An enablement module demonstrating intelligent lookalike modeling in Snowflake. A Cortex Agent equipped with a SKILL.md-based skill browses the Snowflake Feature Store to select and compose features, trains an XGBoost classifier, scores a consumer universe, and reports results in plain business language. The data science team monitors agent-created models via experiment tracking, lift analysis, and quality gates.

## Audience

Data scientists, ML engineers, solutions architects, and technical leaders evaluating Snowflake for self-service ML at scale — particularly in marketing analytics and audience modeling.

## Topics Covered

- Lookalike modeling: seed audience expansion via binary classification
- Snowflake Feature Store: governed feature catalog, feature views, entities, generate_training_set
- Cortex Agent Skills: SKILL.md discovery, Python script execution via code_execution tool
- Intelligent feature selection: LLM reasoning + statistical validation (mutual information, correlation)
- Model Registry and Experiment Tracking: versioned models, run comparison, feature set logging
- Validation: cumulative gains charts, lift-by-decile analysis, decile profiling
- Model monitoring: PSI drift detection, automated quality gates
- Self-service ML: non-technical users trigger models, DS team governs outputs

## Architecture

```
User (CoWork) → Cortex Agent → discovers SKILL.md → executes Python scripts
                                                         ↓
                                    Feature Store (5 feature views)
                                                         ↓
                              Train XGBoost → Model Registry + Experiments
                                                         ↓
                                    Score Universe → Decile Rankings
                                                         ↓
                              DS Team: Lift Analysis, PSI, Quality Gates
```

## Contents

| File | Description |
|------|-------------|
| `presentations/lookalike-modeling.html` | Slide deck (14 slides) |
| `presentations/lookalike-modeling-speaker-notes.md` | Per-slide speaker notes with Quad context |
| `lab/setup.sql` | SQL setup script (database, warehouse, synthetic data) |
| `lab/lookalike-modeling-lab.ipynb` | Hands-on lab notebook (45-60 min) |

## Hands-On Lab

The lab walks participants through both sides of agentic lookalike modeling:

**Part 1 — Building the System (Sections 1-7):** Set up the Feature Store with governed feature views, create the agent skill (SKILL.md + Python scripts), deploy the Cortex Agent, and invoke it 3 times with different seed audiences to observe intelligent feature selection.

**Part 2 — DS Monitoring (Sections 8-13):** Query experiment runs, validate models with cumulative gains and lift charts, audit the agent's feature selections, detect drift via PSI, and apply automated quality gates.

### Prerequisites

- A Snowflake account with ML features enabled (Feature Store, Model Registry, Cortex Agents, code_execution tool)
- A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE AGENT privileges
- Python environment with `snowflake-ml-python >= 1.18.0`, `xgboost`, `numpy`, `pandas`

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `LOOKALIKE_DEMO` database with schemas: RAW, FEATURE_STORE, MODELS, SCORING, MONITORING
- `LOOKALIKE_WH` warehouse (MEDIUM, auto-suspend 120s)
- `SKILL_STAGE` internal stage for agent skill files
- `CONSUMER_UNIVERSE` — 100,000 synthetic consumers with demographics and geo
- `PURCHASE_HISTORY` — 500,000 purchases over 12 months across 8 categories
- `CHANNEL_ENGAGEMENT` — 300,000 multi-channel engagement signals
- `CAMPAIGN_SEEDS` — 3 seed audiences (~1,000 consumers each)

### Lab Sections

1. Setup and imports
2. Explore source data (universe, seeds, distributions)
3. Feature Store initialization (entities, feature views)
4. Register feature views with descriptions
5. Create skill files (SKILL.md, profile_and_select.py, train_and_score.py)
6. Create the Cortex Agent with skill reference
7. Invoke agent with 3 different seeds (observe feature selection differences)
8. Experiment dashboard (query runs, compare metrics)
9. Cumulative gains and lift analysis
10. Feature selection audit (validate agent's choices)
11. PSI drift detection
12. Quality gates (automated pass/fail, registry tagging)
13. Summary and next steps

## Key Concepts

- **Agent Skill (SKILL.md)** — A portable package of instructions and scripts stored on a stage. The agent discovers it by name/description and executes it when relevant. Unlike orchestration instructions, skills are versionable, shareable, and can include Python scripts.
- **Feature Store** — Centralized, governed feature catalog. The agent browses registered feature views to understand what features are available, rather than querying raw tables directly.
- **Lookalike Model** — Binary classifier trained on seed (label=1) vs. non-seed (label=0). The scored universe is ranked into deciles; top deciles are the "lookalike audience" for campaign activation.
- **Quality Gates** — Automated validation that checks AUC, lift, PSI, and feature coherence before marking a model as production-ready.

## Customer Context

This module addresses the workflow described by Quad/Rise's data science team:
- Non-technical users (account managers, media planners) trigger lookalike models
- 750+ monthly models need monitoring at scale
- "5-minute lookalike model" runtime target
- DS team needs to "gut-check quickly" that agent-created models make sense
- 260M person universe with 20,000+ attributes (simulated at smaller scale here)

## References

- [Cortex Agent Skills](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
- [Cortex Agent Code Execution](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-code-execution-tool)
- [Snowflake Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Working with Feature Views](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/feature-views)
- [Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview)
- [Experiment Tracking](https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiment-tracking)
