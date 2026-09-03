# Patient Adherence Targeting with Snowflake ML

A hands-on lab demonstrating patient targeting for pharmacy adherence programs using Snowflake's ML platform. Built for data scientists evaluating Snowflake for clinical ML workloads.

## The Problem

A pharma manufacturer funds a limited number of intervention slots (say 1,000) for a pharmacy adherence program. The pharmacy needs to decide: **which 1,000 patients are most likely to respond (fill their prescription) after outreach?**

This lab builds a targeting system that scores every patient in the universe, ranks them by predicted response probability, and extracts the top N for each program.

## Architecture

```
Patient Universe + Rx History + Program Outcomes
                    ↓
    Feature Store (5 governed feature views)
                    ↓
    generate_training_set() → labeled training data
                    ↓
    XGBoost binary classifier (responder vs non-responder)
                    ↓
    Model Registry + Experiment Tracking
                    ↓
    Score Universe → Decile Rankings → Top N Patient List
                    ↓
    Lift Analysis, Quality Gates, Feature Audit
```

## Topics Covered

- **Feature Store**: entities, feature views, `generate_training_set()` for point-in-time correct features
- **XGBoost**: binary classification for patient response prediction
- **Model Registry**: versioned model storage with metrics, comments, and governance tags
- **Experiment Tracking**: compare models across programs, feature sets, and hyperparameters
- **Lift Analysis**: cumulative gains charts, lift-by-decile validation
- **Quality Gates**: automated pass/fail with registry tagging (APPROVED / NEEDS_REVIEW)
- **Cortex Agent** (bonus): natural language interface for triggering targeting models

## Synthetic Data

The lab generates synthetic data that mirrors real pharmacy benefit manager tables:

| Table | ~Rows | Description |
|-------|-------|-------------|
| `PATIENT_UNIVERSE` | 50,000 | Demographics, payer type, zip income, urbanicity, PDC, diagnosis availability |
| `PRESCRIPTION_HISTORY` | ~250,000 | 18 months of Rx fills across 11 therapeutic classes |
| `ADHERENCE_PROGRAMS` | 18 | Manufacturer-funded programs: Secondary Adherence, Support Services, Primary Adherence |
| `PROGRAM_OUTCOMES` | ~30,000 | Per-patient program outcomes: got_fill, days_to_fill, pre/post PDC |

Response rates are correlated with patient characteristics (income, PDC, engagement history) to create learnable signal for the ML model.

## Prerequisites

- A Snowflake account with ML features enabled (Feature Store, Model Registry, Experiment Tracking)
- A role with CREATE DATABASE, CREATE WAREHOUSE privileges
- Python packages: `snowflake-ml-python >= 1.18.0`, `xgboost`, `numpy`, `pandas`, `scikit-learn`, `matplotlib`
- For the bonus agent section: Cortex Agents and `code_execution` tool enabled

## Setup

1. Run `lab/setup.sql` in a Snowflake worksheet or via SnowSQL
2. Open `lab/patient-targeting-lab.ipynb` in Snowflake Workspaces (or locally with a Snowpark connection)

The setup script creates:
- `PATIENT_TARGETING_DEMO` database with schemas: RAW, FEATURE_STORE, MODELS, SCORING, MONITORING
- `PATIENT_TARGETING_WH` warehouse (MEDIUM, auto-suspend 120s)
- All synthetic data tables

## Lab Sections

### Part 1 — Building the Targeting Model (Sections 1-8)
1. Setup and imports
2. Explore patient, program, and outcome data
3. Feature Store: entity and 5 feature views (demographics, medication behavior, therapeutic class affinity, engagement history, clinical complexity)
4. Generate training set from program responders (seed) vs non-responders
5. Train XGBoost classifier with feature importance analysis
6. Score patient universe, rank into deciles, extract top N for outreach
7. Register model in Model Registry with metrics
8. Log experiment for cross-run comparison

### Part 2 — Validation & Monitoring (Sections 9-12)
9. Lift analysis: cumulative gains and lift-by-decile charts
10. Feature importance audit: validate against clinical domain knowledge
11. Iterate: train a second model for a different program type, compare feature importance
12. Quality gates: automated pass/fail, registry tagging

### Part 3 — Bonus: Agent-Powered Targeting (Section 13)
13. Cortex Agent with SKILL.md for natural language targeting requests (optional)

### Part 4 — Summary & Next Steps (Section 14)
14. Mapping synthetic tables to real data, production path

## Mapping to Real Data

| Synthetic Table | Your Table | Swap Guide |
|---|---|---|
| `PATIENT_UNIVERSE` | Patient characteristics | Match column names in Feature View SQL |
| `PRESCRIPTION_HISTORY` | Rx fill data | Adjust GPI/NDC column references |
| `ADHERENCE_PROGRAMS` | Program definitions | Add your actual programs |
| `PROGRAM_OUTCOMES` | Program outcomes | Point spine query at your outcomes table |

The Feature Store queries are the only place where table/column names matter. Everything downstream (training, scoring, registry, experiments) uses the Feature Store abstraction and stays unchanged.

## References

- [Snowflake Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Working with Feature Views](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/feature-views)
- [Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview)
- [Experiment Tracking](https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiment-tracking)
- [Cortex Agent Skills](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
