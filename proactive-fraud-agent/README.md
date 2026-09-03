# Proactive Fraud Detection with Snowflake Cortex

End-to-end fraud detection pipeline: synthetic data → dynamic tables → feature store → ML model (SHAP) → agent investigation → SAR investigation portal.

## Architecture

```
RAW DATA (500K transactions, 10K customers, 1K merchants)
    ↓ change tracking
DYNAMIC TABLES (enrichment + per-customer aggregates)
    ↓ 5-min lag
FEATURE STORE (entity + managed feature view)
    ↓
GRADIENT BOOSTING + SHAP (model registry + per-customer explanations)
    ↓
PRIORITIES TABLE (top 100 fraud risks)
    ↓
CORTEX AGENT (investigates each priority, writes reports with thread_id)
    ↓
INVESTIGATION PORTAL (SAR/Next.js: SHAP charts + reports + chat continuation)
```

## Prerequisites

- Snowflake account with Cortex AI enabled
- Role with CREATE DATABASE, CREATE WAREHOUSE privileges
- Python 3.11+ with `snowflake-ml-python`, `shap`, `scikit-learn`
- Node.js 18+ (for the app)
- Snow CLI (`snow`) configured with a connection named `parker_demo`

## Deployment

### 1. Run SQL setup scripts (in order)

```bash
snow sql -f setup/01_foundations.sql -c parker_demo
snow sql -f setup/02_feature_pipeline.sql -c parker_demo
```

Wait ~5 minutes for dynamic tables to refresh, then:

### 2. Run Python scripts

```bash
python setup/03_feature_store.py
python setup/04_train_xgboost.py
```

### 3. Run scoring and agent setup

```bash
snow sql -f setup/05_score_priorities.sql -c parker_demo
snow sql -f setup/06_agent_investigate.sql -c parker_demo
```

### 4. (Optional) Run investigation batch

```sql
CALL APP.RUN_INVESTIGATION_BATCH(10);
```

### 5. Deploy the app

```bash
cd app
npm install
npm run dev
```

## Key Objects

| Object | Type | Description |
|--------|------|-------------|
| `RAW.TRANSACTIONS` | Table | 500K synthetic transactions (5 fraud patterns) |
| `RAW.CUSTOMERS` | Table | 10K customers (500 flagged as fraud) |
| `RAW.MERCHANTS` | Table | 1K merchants |
| `CURATED.TRANSACTIONS_ENRICHED` | Dynamic Table | Enriched with distance, ratios, time features |
| `CURATED.CUSTOMER_FEATURE_BASE` | Dynamic Table | Per-customer 1h/24h/7d aggregates |
| `FEATURES.FRAUD_FEATURES$V1` | Feature View | Managed feature view (18 features) |
| `FEATURES.SHAP_SUMMARY` | Table | Per-customer SHAP explanations |
| `MODELS.FRAUD_DETECTOR` | Model | Registered GradientBoosting model (V1) |
| `APP.PRIORITIES` | Table | Top 100 fraud-risk customers |
| `APP.INVESTIGATION_REPORTS` | Table | Agent investigation outputs with thread_id |
| `APP.RUN_INVESTIGATION_BATCH` | Procedure | Iterates priorities, calls Cortex, stores reports |
| `APP.INVESTIGATE_TASK` | Task | 5-min scheduled investigation (suspended by default) |

## Fraud Patterns (Synthetic)

1. **VELOCITY** — 100 customers with rapid-fire transactions (100 txns/hour)
2. **STRUCTURING** — 100 customers with amounts just below $10K threshold
3. **GEO_ANOMALY** — 100 customers with transactions far from home (Europe/Africa)
4. **RETURN_ABUSE** — 100 customers with high purchase-then-refund cycles
5. **NEW_MERCHANT** — 100 customers with sudden spending at many new merchants
