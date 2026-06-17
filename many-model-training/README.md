# Many-Model Training on Snowflake

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/many-model-training/presentations/many-model-training.html)

An enablement module covering end-to-end Many-Model Training (MMT) on Snowflake — from Feature Store setup through distributed training, model registration, experiment tracking, and AI-powered monitoring. Uses retail demand forecasting as the example domain.

## Audience

Data scientists, ML engineers, solutions architects, and technical leaders evaluating Snowflake for entity-level ML workloads (demand forecasting, IoT, fleet management, customer segmentation).

## Topics Covered

- The problem: global models miss local patterns, multi-tool pipelines, manual retraining
- The MMT mental model: one pipeline → thousands of specialist models
- Feature Store: entities, versioned feature views, point-in-time correct datasets
- Training: ManyModelTraining API, Distributed Partition Functions (DPF), XGBoost + SHAP
- Model Registry: CustomModel with `@partitioned_api`, partitioned inference
- Inference: batch scoring via `mv.run()` with `partition_column`
- Telemetry & Drift: rolling MAPE, drift flags, selective retraining
- Experiments: champion vs challenger per-partition comparison, ExperimentTracking API
- Agent Monitoring: Cortex COMPLETE for root cause analysis and recommendations
- Scaling: compute pools, partition counts, production patterns

## Contents

| File | Description |
|------|-------------|
| `presentations/many-model-training.html` | Slide deck (14 slides) |
| `presentations/many-model-training-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, Feature Store, synthetic data generation) |
| `lab/many-model-training-lab.ipynb` | Hands-on lab notebook (45-60 min) |
| `lab/poc/config.yaml` | Domain configuration (stores, items, features, training params) |
| `lab/poc/utils.py` | Session management, config loading, stage utilities |
| `lab/poc/feature_store.py` | Feature Store setup and dataset generation |
| `lab/poc/train.py` | Unified training pipeline (champion/challenger/experiment) |
| `lab/poc/register.py` | Model Registry registration (partitioned CustomModel) |
| `lab/poc/infer.py` | Batch inference pipeline |
| `lab/poc/experiment.py` | Experiment tracking and promotion logic |
| `lab/poc/agent_monitor.py` | Cortex Agent monitoring (drift analysis, LLM explanations) |

## Hands-On Lab

The lab walks participants through the full ML lifecycle: Feature Store setup, distributed training, model registration, inference, experimentation, and monitoring.

### Prerequisites

- A Snowflake account with ML features enabled (Feature Store, Model Registry, ML Jobs)
- A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE COMPUTE POOL privileges
- Python environment with `snowflake-ml-python >= 1.29.0`, `xgboost`, `shap`
- For agent monitoring: cross-region inference enabled (for Cortex COMPLETE)

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `MMT_DEMO` database with `FORECASTING` schema
- `MMT_DEMO_WH` warehouse (MEDIUM, auto-suspend 120s)
- `ML_STAGE` internal stage for model artifacts
- `FEATURE_TABLE` — 432,000 rows of synthetic hourly demand data (20 stores × 10 items × 2,160 hours)
- `FEATURE_STORE` schema for Feature Store objects
- Downstream tables: `MODEL_CATALOG`, `FORECAST_TELEMETRY`, `EXPERIMENT_LOG`, `EXPERIMENT_RESULTS`, `AGENT_INSIGHTS`

### Lab Sections

1. Connect & verify setup (confirm FEATURE_TABLE exists with expected row count)
2. Set up Feature Store (entity + 3 feature views: base, weather, rolling)
3. Generate training dataset from Feature Store (point-in-time correct join, 90/10 split)
4. Train champion model via ManyModelTraining (200 XGBoost models with SHAP)
5. Register to Model Registry as partitioned CustomModel
6. Run batch inference, populate telemetry with drift flags
7. Train challenger with weather features, run experiment, compare per-partition
8. (Optional) Run agent-powered monitoring with Cortex COMPLETE

## Key Concepts

- **Many-Model Training (MMT)** — Train one model per entity partition (store-item, device, customer) using a single pipeline. DPF handles parallelism across a compute pool.
- **Feature Store** — Versioned feature management. Every model records which feature view versions produced it, enabling reproducible experiments.
- **Partitioned CustomModel** — `@partitioned_api` decorator routes inference to the correct per-partition model automatically.
- **Selective Retraining** — Monitor per-partition MAPE, retrain only models that drift past threshold. Not blind weekly retraining.

## References

- [Snowflake Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Snowflake Model Registry](https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview)
- [Many-Model Training (ML Jobs)](https://docs.snowflake.com/en/developer-guide/snowflake-ml/modeling/many-model-training)
- [Experiment Tracking](https://docs.snowflake.com/en/developer-guide/snowflake-ml/experiment-tracking/overview)
- [Cortex COMPLETE](https://docs.snowflake.com/en/sql-reference/functions/complete-snowflake-cortex)
