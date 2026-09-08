# Marketing Command Center — Implementation Plan

## Architecture Overview

A React dashboard ("Marketing Command Center") backed by:

- **Snowflake Feature Store** — governed, versioned ML features for customer, product, and POS data
- **Many Model Training (MMT)** — XGBoost demand forecasting models trained per retailer x brand partition
- **Model Registry** — XGBoost/LightGBM models logged with metrics, versioned, and served via warehouse inference
- **Cortex Agent** — embedded in the React app, can reason over predictions + underlying data via semantic views
- **Self-Serve Lookalike Builder** — React UI where marketing selects feature sets from the Feature Store, defines a seed audience, and triggers a new model build

---

## Component 1: Feature Store (Foundation Layer)

### Entities

- **customer** — keys: `[CUSTOMER_ID]` (from CUSTOMER_OMNI_V)
- **product** — keys: `[SKU]` or `[UPC]` (from POS + order lines)
- **retailer_product_week** — keys: `[RETAILER_NAME, ITEM_BRAND, RETAILER_DATE]` (POS time-series)

### Feature Views

| Feature View | Entity | Source Table | Key Features |
|---|---|---|---|
| `CUSTOMER_RFM_FV` | customer | CUSTOMER_OMNI_V | recency, frequency, monetary, brand_diversity, discount_sensitivity, prorewards_flag |
| `CUSTOMER_BEHAVIOR_FV` | customer | WEB_ORDERS_V + lines | avg_basket_size, coupon_usage_rate, product_category_mix, geography |
| `POS_WEEKLY_SALES_FV` | retailer_product_week | POS_RETAIL_DETAILS_F | gross_units_sold, net_sales_retail, inventory_on_hand, markdown_pct, return_rate |
| `PRODUCT_PERFORMANCE_FV` | product | POS_RETAIL_DETAILS_F | avg_sell_through_rate, distribution_breadth, avg_price, margin |

All feature views are Snowflake-managed with `refresh_freq` (e.g., daily for POS, hourly for DTC), giving marketing a governed catalog of features to build models from.

---

## Component 2: Demand Forecasting via MMT

**Approach:** Many Model Training with XGBoost regressors, one model per `RETAILER_NAME x ITEM_BRAND` partition.

### Steps

1. Build training view from `POS_WEEKLY_SALES_FV` with lag features (t-1 through t-8 weeks), rolling averages, seasonality indicators
2. Define training function: `XGBRegressor` per partition predicting `GROSS_AMT_SOLD_UNITS` for next 8 weeks
3. Run `ManyModelTraining(train_fn, "FORECAST_MODELS_STAGE")` partitioned by composite key
4. Log the best model per partition to the Model Registry with metrics (MAPE, RMSE)
5. Serve predictions via `model_version.run()` on a scheduled task (weekly refresh)
6. Store forecasts in a results table that the Cortex Agent can query

**Key win for demo:** Show the Model Registry UI with versioned models, metrics comparison between versions, and explainability (SHAP feature importance).

---

## Component 3: Customer Propensity & Lookalike Models (Model Registry)

### Pre-built Models (logged to registry)

- **customer_repurchase_xgb** — XGBClassifier predicting 90-day repurchase
- **customer_ltv_xgb** — XGBRegressor predicting 12-month spend
- **customer_churn_xgb** — XGBClassifier predicting 180-day inactivity

### Self-Serve Lookalike Builder (the key marketing demo)

The React dashboard exposes a UI flow:

1. Marketing selects a seed audience (e.g., upload a list of customer IDs, or filter: "bought Peak Hydro 3+ times")
2. Dashboard queries the Feature Store API to show available features from registered feature views
3. Marketing picks features (or uses recommended defaults)
4. React calls a Snowflake stored procedure that:
   - Pulls features via `fs.generate_training_set()` with the selected feature views
   - Trains an `XGBClassifier` (seed vs. non-seed)
   - Logs to Model Registry with `reg.log_model()`
   - Runs inference on full customer base
   - Returns top-N lookalike customers ranked by propensity score
5. Dashboard shows results + SHAP explainability

---

## Component 4: Cortex Agent (Conversational Intelligence)

### Agent Setup

- **Semantic View** covering: forecast results table, customer scores table, POS actuals, feature store outputs
- **Tools:**
  - `cortex_analyst_text_to_sql` — query predictions, actuals, features
  - `data_to_chart` — visualize results inline
  - Custom tool (stored procedure) — trigger model re-scoring or explain a specific prediction

### Example Interactions

- "What's the forecasted sell-through for Peak Hydro at Walmart next month?"
- "Which customers are most likely to churn who bought ChefLine last quarter?"
- "Compare actual vs predicted sales for Target in Q3"
- "Why was customer X scored as high-risk?"

---

## Component 5: React Dashboard

**Tech Stack:** React + Vite, deployed as a Snowflake App (SAR) or standalone with Snowflake REST API auth.

### Pages/Views

1. **Forecast Dashboard** — time-series charts of predicted vs actual by retailer/brand, model performance metrics from registry
2. **Customer Intelligence** — segment distribution, propensity scores, cohort trends
3. **Lookalike Builder** — self-serve UI (seed selection -> feature picker from Feature Store -> train -> results)
4. **Model Registry** — display registered models, versions, metrics, lineage
5. **Agent Chat Panel** — embedded Cortex Agent sidebar for conversational Q&A across all data

---

## Implementation Order

1. Feature Store setup — entities, feature views, register
2. MMT forecasting pipeline — training function, schedule, results table
3. Customer models — train, log to registry
4. Semantic view + Cortex Agent — wire up predictions + actuals
5. React dashboard — scaffold app, build pages, embed agent
6. Lookalike builder — stored procedure + React UI flow

---

## Key Files to Create

1. `notebooks/01_feature_store_setup.ipynb` — Feature Store entities + feature views
2. `notebooks/02_mmt_forecasting.ipynb` — MMT XGBoost demand forecasting pipeline
3. `notebooks/03_customer_models.ipynb` — Customer propensity models + registry
4. `sql/semantic_view.sql` — Semantic view DDL for the Cortex Agent
5. `sql/agent.sql` — CREATE AGENT with tools
6. `app/` — React dashboard (SAR app or standalone)
7. `procedures/lookalike_builder.py` — Stored procedure for self-serve model training

---

## Verification

- **Feature Store:** `fs.list_feature_views()` shows all registered FVs with correct refresh status
- **Models:** `reg.show_models()` lists forecast + customer models with metrics
- **MMT:** Partition-level models retrievable from stage, predictions match actuals within expected MAPE
- **Agent:** Ask sample questions, verify SQL generation against semantic view
- **Dashboard:** All pages render with live data from Snowflake
