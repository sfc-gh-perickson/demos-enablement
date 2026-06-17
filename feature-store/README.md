# Snowflake Feature Store: Define Once, Serve Everywhere

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/feature-store/presentations/feature-store.html)

An enablement module covering the Snowflake Feature Store end-to-end — from entity definition and feature engineering through offline training datasets, online serving with sub-second lookups, and real-time model inference integration. Uses e-commerce personalization (product recommendations) as the example domain.

## Audience

Data scientists, ML engineers, solutions architects, and technical leaders evaluating Snowflake for feature management across batch training and real-time serving workloads.

## Topics Covered

- The problem: feature drift, training/serving skew, duplicated pipelines, temporal leakage
- Architecture: offline store (dynamic tables) + online store (hybrid tables)
- Entities & Feature Views: logical organization, versioning, governance
- Feature engineering: raw vs engineered views, SQL/Snowpark transforms
- Point-in-time correctness: spine-based joins, temporal leak prevention
- Dataset generation: `fs.generate_training_set()` for reproducible ML
- Online Feature Store: hybrid table-backed, configurable `target_lag`, incremental refresh
- Real-time serving: `StoreType.ONLINE` reads, sub-second lookups
- Model integration: `feature_sources_per_function` for auto-lookup at inference time
- Monitoring: refresh history, cost tracking, drift detection
- Governance: RBAC, lineage, feature discoverability
- Production patterns: batch + real-time from single feature definitions

## Contents

| File | Description |
|------|-------------|
| `presentations/feature-store.html` | Slide deck (14 slides) |
| `presentations/feature-store-speaker-notes.md` | Per-slide speaker notes with talking points, internal context, and references |
| `lab/setup.sql` | SQL setup script (database, warehouse, synthetic e-commerce data generation) |
| `lab/feature-store-lab.ipynb` | Hands-on lab notebook (45-60 min) |

## Hands-On Lab

The lab walks participants through the full feature store lifecycle: entity setup, feature view registration, engineered features, training dataset generation, model training, online serving enablement, real-time retrieval, and model inference integration.

### Prerequisites

- A Snowflake account with ML features enabled (Feature Store, Model Registry, Online Feature Tables)
- A role with CREATE DATABASE, CREATE WAREHOUSE privileges
- Python environment with `snowflake-ml-python >= 1.18.0`, `xgboost`
- For online serving: Snowflake version 9.26 or later

### Setup

Run `lab/setup.sql` in your Snowflake account. This creates:

- `FEATURE_STORE_DEMO` database with `RAW`, `FEATURE_STORE`, `MODELS`, `SCORING` schemas
- `FS_DEMO_WH` warehouse (MEDIUM, auto-suspend 120s)
- `ML_STAGE` internal stage for model artifacts
- `CUSTOMER_PROFILE` — 10,000 synthetic customers with demographics and spend metrics
- `PRODUCT_CATALOG` — 1,000 products across 8 categories
- `PURCHASE_HISTORY` — 200,000 purchases over 12 months
- `BROWSE_EVENTS` — 500,000 browsing events over 30 days
- `PRODUCT_DAILY_METRICS` — 30,000 daily product performance metrics

### Lab Sections

1. Connect & verify setup (confirm tables exist with expected row counts)
2. Feature Store initialization (create Feature Store, define entities)
3. Register raw feature views (customer profile, product catalog, purchase history)
4. Build engineered feature views (RFM scores, behavioral aggregates, product popularity)
5. Generate training dataset (point-in-time correct join, positive/negative sampling)
6. Train recommendation model (XGBoost binary classifier, evaluate AUC/precision/recall)
7. Enable online serving (OnlineConfig with target_lag)
8. Real-time feature retrieval (StoreType.ONLINE lookups, latency comparison)
9. Deploy model with online feature integration (feature_sources_per_function)
10. Monitor operations (refresh history, cost queries, drift detection)

## Key Concepts

- **Feature Store** — Centralized feature management. Define features once from source data, serve them both offline (for training) and online (for real-time inference) without code duplication.
- **Online Feature Store** — Hybrid table-backed replicas that provide sub-second point lookups. Automatically synced from the offline store with configurable freshness (10 seconds to 8 days).
- **Point-in-Time Correctness** — Temporal joins that prevent future data from leaking into training examples. Each training row sees only features available at that point in time.
- **Feature Sources Per Function** — Model inference endpoints auto-fetch features from the online store at request time. Send only entity keys, get predictions back.

## References

- [Snowflake Feature Store](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview)
- [Create and Serve Online Features](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/create-and-serve-online-features-python)
- [Use Online Feature Store in Production](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/use-online-feature-store-in-production)
- [Working with Feature Views](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/feature-views)
- [Advanced Feature Engineering](https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/advanced-feature-engineering)
- [Deploy Models for Real-Time Inference](https://docs.snowflake.com/en/developer-guide/snowflake-ml/inference/real-time-inference-rest-api)
