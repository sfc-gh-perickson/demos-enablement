# Summit Brands — Marketing Command Center

A Snowflake-native ML demo for Summit Brands's marketing team. Shows Feature Store, Model Registry, ML Jobs (XGBoost), Cortex Agent, and a React dashboard with self-serve lookalike modeling.

## Prerequisites

- Snowflake account with the `my_connection` connection configured in `~/.snowflake/connections.toml`
- Python 3.11 with `snowflake-ml-python>=1.50.0`, `snowflake-snowpark-python`, `xgboost`, `scikit-learn`
- Compute pool `ML_CPU_POOL` available (auto-resumes on job submit)
- `snow` CLI installed (for SAR app deployment)
- Warehouse `COMPUTE_WH` accessible to your role

## Project Structure

```
├── notebooks/
│   ├── 00_setup_demo_data.ipynb      # Database + synthetic data (run first)
│   ├── 01_feature_store_setup.ipynb  # Feature Store entities + feature views
│   ├── 02_mmt_forecasting.ipynb      # Demand forecasting (ML Job + Registry)
│   └── 03_customer_models.ipynb      # Repurchase/LTV models (ML Job + Registry)
├── sql/
│   ├── semantic_view.sql             # Semantic view for Cortex Agent
│   └── agent.sql                     # Cortex Agent definition
├── procedures/
│   └── lookalike_builder.py          # Self-serve lookalike stored procedure
├── app/                              # React dashboard (SAR app)
│   ├── app.yml                       # SAR v2 deployment manifest
│   ├── Dockerfile                    # Build + serve config
│   ├── nginx.conf
│   ├── package.json
│   ├── src/
│   │   ├── App.tsx                   # Router + layout
│   │   ├── main.tsx                  # Entry point
│   │   ├── api/
│   │   │   ├── snowflake.ts          # Snowflake SQL API client
│   │   │   └── agent.ts             # Cortex Agent SSE client
│   │   ├── pages/
│   │   │   ├── ForecastDashboard.tsx
│   │   │   ├── CustomerIntelligence.tsx
│   │   │   ├── LookalikeBuilder.tsx
│   │   │   └── ModelRegistry.tsx
│   │   └── components/
│   │       ├── AgentChat.tsx         # Embedded agent chat sidebar
│   │       └── FeatureSelector.tsx   # Feature Store feature picker
│   └── vite.config.ts
```

## Deployment Steps

### Step 1: Create Database + Demo Data

Run `notebooks/00_setup_demo_data.ipynb` cell by cell. This creates:

- Database `SB_COMMAND_CENTER` with schemas: `RAW`, `FEATURE_STORE`, `FORECASTING`, `MODELS`, `REGISTRY`, `SCORING`, `SEMANTIC`, `AGENTS`, `PROCEDURES`
- `RAW.POS_SALES` (~500K rows) — weekly POS sell-through across 5 retailers × 5 brands with seasonality, markdown correlation, and retailer-specific baselines
- `RAW.CUSTOMER_TRANSACTIONS` (~213K rows) — 50K customers with 4 distinct segments (loyalists, deal-seekers, occasional, one-time)
- `RAW.WEB_ORDERS` (100K rows) + `RAW.WEB_ORDER_LINES` (~354K rows) — DTC orders with coupon patterns and geographic brand affinity

The data has intentionally strong learnable patterns so the ML models produce meaningful results.

### Step 2: Feature Store

Run `notebooks/01_feature_store_setup.ipynb`. Creates:

| Feature View | Entity | Source | Refresh |
|---|---|---|---|
| `CUSTOMER_RFM_FV` | CUSTOMER | CUSTOMER_TRANSACTIONS | Daily 6am CT |
| `CUSTOMER_BEHAVIOR_FV` | CUSTOMER | WEB_ORDERS + WEB_ORDER_LINES | Daily 6am CT |
| `POS_WEEKLY_SALES_FV` | RETAILER_PRODUCT_WEEK | POS_SALES | Monday 4am CT |

Each feature view is backed by a Snowflake dynamic table with automatic refresh. The `block=True` parameter ensures the initial data load completes before you proceed.

If you get a `SNOWML_FEATURE_STORE_OBJECT does not exist` error, the notebook handles this via `CreationMode.CREATE_IF_NOT_EXIST`.

### Step 3: Demand Forecasting

Run `notebooks/02_mmt_forecasting.ipynb`. This:

1. Reads POS features from the Feature Store via `fs.read_feature_view()`
2. Adds lag, rolling average, and seasonality features with Snowpark window functions
3. Materializes training data to `FORECASTING.TRAINING_DATA`
4. Submits an **ML Job** to `ML_CPU_POOL` via `@remote` that:
   - Trains 25 XGBoost regressors (one per retailer × brand partition)
   - Pickles each model to `@FORECASTING.ML_STAGE`
   - Writes metrics to `FORECASTING.MODEL_CATALOG`
   - Logs the best model to the **Model Registry** (`SB_COMMAND_CENTER.REGISTRY`)
   - Generates 8-week forecasts to `SCORING.DEMAND_FORECASTS`
5. Verification cells query the forecast output and model catalog

The compute pool auto-resumes when the job is submitted. Expect ~2-5 minutes for the full training run.

### Step 4: Customer Propensity Models

Run `notebooks/03_customer_models.ipynb`. This:

1. Builds training labels from transaction history (repurchase within 90 days, 6-month LTV)
2. Pulls features from both customer feature views via `fs.generate_training_set()`
3. Materializes to `SCORING.CUSTOMER_TRAINING_DATA`
4. Submits an **ML Job** that:
   - Trains an XGBClassifier (repurchase propensity) and XGBRegressor (LTV)
   - Logs both to the Model Registry
   - Scores all 50K customers
   - Assigns segments: Champion, Engaged, Moderate, At Risk
   - Writes to `SCORING.CUSTOMER_SCORES`

### Step 5: Semantic View + Cortex Agent

Run the SQL files against Snowflake:

```bash
snow sql -f sql/semantic_view.sql
snow sql -f sql/agent.sql
```

Or execute each file's contents in a Snowflake worksheet.

The **semantic view** (`SEMANTIC.MARKETING_COMMAND_CENTER_SV`) covers all four tables with metrics, relationships, and column descriptions so the Cortex Agent can generate accurate SQL.

The **Cortex Agent** (`AGENTS.MARKETING_COMMAND_CENTER`) uses `cortex_analyst_text_to_sql` + `data_to_chart` tools. Example questions it handles:
- "What's the forecasted sell-through for Peak Hydro at Walmart next month?"
- "Which customer segments have the highest LTV?"
- "Show me a chart of POS sales by brand over time"
- "Compare forecast accuracy across retailers"

### Step 6: Lookalike Builder Procedure

```bash
bash procedures/deploy_lookalike.sh
```

This creates the stage, uploads the Python file, and registers the stored procedure. Test it:

```sql
CALL SB_COMMAND_CENTER.PROCEDURES.BUILD_LOOKALIKE(
    ARRAY_CONSTRUCT('CUST-000001', 'CUST-000002', 'CUST-000010', 'CUST-000050'),
    ARRAY_CONSTRUCT('CUSTOMER_RFM_FV', 'CUSTOMER_BEHAVIOR_FV'),
    'test_lookalike'
);
```

### Step 7: React Dashboard (Local Dev)

```bash
cd app
npm install
npm run dev
```

The Vite dev server starts at `http://localhost:5173`. It reads your `~/.snowflake/config.toml` (`my_connection` connection) at startup, and proxies `/api/` requests to Snowflake with the PAT from your config — no `.env` or extra setup needed.

The dashboard has four pages:
- **Forecast Dashboard** — demand forecast charts by retailer/brand
- **Customer Intelligence** — segment breakdown, propensity distributions
- **Lookalike Builder** — self-serve: pick seed audience, select features, train, view results
- **Model Registry** — browse registered models, versions, metrics

The embedded **Agent Chat** sidebar calls the Cortex Agent via SSE streaming (`POST /api/v2/cortex/agent:run`).

#### SPCS Deployment (optional)

To deploy to Snowpark Container Services instead of running locally:

```bash
bash app/deploy_app.sh
```

This builds a Docker image (`linux/amd64`), pushes it to the Snowflake image registry, and creates an SPCS service on `SB_APP_POOL`. The script prints the app URL when the service is ready.

## Snowflake Objects Created

| Schema | Objects |
|---|---|
| `RAW` | POS_SALES, CUSTOMER_TRANSACTIONS, WEB_ORDERS, WEB_ORDER_LINES |
| `FEATURE_STORE` | Entities (CUSTOMER, RETAILER_PRODUCT_WEEK), Feature Views (CUSTOMER_RFM_FV, CUSTOMER_BEHAVIOR_FV, POS_WEEKLY_SALES_FV) + backing dynamic tables |
| `FORECASTING` | TRAINING_DATA, MODEL_CATALOG, ML_STAGE (internal stage with pickled models) |
| `REGISTRY` | demand_forecast_xgb, customer_repurchase_xgb, customer_ltv_xgb (model objects) |
| `SCORING` | DEMAND_FORECASTS, CUSTOMER_SCORES, CUSTOMER_TRAINING_DATA |
| `SEMANTIC` | MARKETING_COMMAND_CENTER_SV (semantic view) |
| `AGENTS` | MARKETING_COMMAND_CENTER (Cortex Agent) |
| `PROCEDURES` | BUILD_LOOKALIKE (stored procedure), PROC_STAGE |

## Cleanup

```sql
DROP DATABASE IF EXISTS SB_COMMAND_CENTER;
```

This removes all schemas, tables, models, feature views, the agent, and the semantic view.
