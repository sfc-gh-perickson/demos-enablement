# Graph-Based Fraud Ring Detection

Detect fraud rings using GPU-accelerated graph community detection on Snowflake,
with real-time feature serving via the Online Feature Store and canary model deployment via Gateway.

## Architecture

```
RAW TABLES (synthetic ~3M applications)
    │
    ▼
EDGE TABLE (Dynamic Table: ring address/IP/device/bank links)
    │
    ├──[SPCS Job, every 15m]──▶ cuGraph Leiden on GPU
    │                               │
    │                               ▼
    │                          COMMUNITY_RESULTS
    │                               │
    ▼                               ▼
Feature Store (5 Feature Views + Postgres online store)
  ├── GRAPH_COMMUNITY_FEATURES  (batch, APPLICANT — community, degree, ring counts)
  ├── ADDRESS_COMMUNITY_FEATURES (batch, ADDRESS — inherited community context)
  ├── IP_COMMUNITY_FEATURES     (batch, IP_NETWORK — inherited community context)
  ├── STREAM_VELOCITY           (stream FV — claim amount, submission hour, velocity)
  └── COMBINED_FRAUD_FEATURES   (real-time FV — experimental, see note below)
    │
    ▼
ML Jobs (XGBoost V1 + Tuner HPO V2) → Model Registry
    │
    ▼
Scoring: parallel OFS REST reads → client-side assembly → Gateway (canary traffic split)
    │
    ▼
Model Monitor (PSI drift on CLAIM_AMOUNT, daily refresh)
```

### Scoring Path

Production scoring does **not** use `feature_sources_per_function` (which only supports one FV
per function). Instead, the scoring path is:

1. **Parallel OFS REST reads** — fetch graph, address, IP, and velocity features concurrently
   (~235ms from laptop / ~10ms in-region)
2. **Client-side assembly** — merge the 4 feature vectors into the 15-feature model input
3. **Gateway call** — send assembled features to the Gateway endpoint (~50ms)

The `COMBINED_FRAUD_FEATURES` real-time FV is **experimental** — it works via the Python SDK
but is not used in the production path due to the single-FV-per-function limitation and
failures for new applicants not yet in the graph FV online store.

## Snowflake Features Used

| Feature | Purpose |
|---|---|
| **Dynamic Tables** | Edge construction (incremental refresh from APPLICATIONS) |
| **SPCS Job Service** | GPU-accelerated cuGraph Leiden community detection |
| **Feature Store** | 5 FVs (3 batch + stream + real-time), Postgres online store |
| **Online Feature Store** | Postgres-backed ~10ms p50 feature reads for 3 entities |
| **Stream Feature View** | Sub-3s freshness for application velocity features |
| **Real-time Feature View** | Experimental: assembles 15 features at query time (not used in production path) |
| **ML Jobs** | XGBoost training on compute pool |
| **Tuner API** | BayesOpt HPO (10 trials, 5 hyperparameters) |
| **Model Registry** | Versioned models (V1 baseline, V2 tuned) |
| **SPCS Inference** | Model services deployed via Registry create_service |
| **Snowflake Gateway** | Canary traffic split (100/0 → 90/10 → 50/50 → 0/100) |
| **Model Monitor** | PSI drift detection on inference autocapture DT |

## Prerequisites

- Snowflake account with ACCOUNTADMIN (or equivalent privileges)
- GPU compute pool access (GPU_NV_S instance family)
- Docker for building the cuGraph container image (use `--platform linux/amd64`)
- `snowflake-ml-python>=1.41` for Postgres online Feature Store
- `SNOWFLAKE_PAT` env var for REST API calls (stream ingest, OFS reads, Gateway)

## Setup

### 1. Create Database, Tables, and Synthetic Data

```sql
-- Run in order:
@setup/01_foundations.sql      -- Database, schemas, ~3M applications, ~100 fraud rings
@setup/02_edge_construction.sql -- Dynamic table: EDGES.APPLICANT_EDGES (ring links)
```

### 2. Deploy SPCS Infrastructure

```sql
@setup/03_spcs_infrastructure.sql -- GPU compute pool, image repo, job service
```

Build and push the Docker image:

```bash
snow spcs image-registry login
docker buildx build --platform linux/amd64 \
  -t <org>-<acct>.registry.snowflakecomputing.com/graph_fraud_demo/graph/image_repo/leiden_job:latest \
  ./spcs --push
```

### 3. Community Assignments Table

```sql
@setup/04_incremental_heuristic.sql -- COMMUNITY_ASSIGNMENTS table for Leiden writes
```

### 4. Run the Notebooks

Open notebooks in Snowflake Notebooks (Container Runtime for NB02 Tuner) or Jupyter:

| Notebook | Description |
|----------|-------------|
| `00_setup.ipynb` | Roles, entities, online service, Leiden trigger |
| `01_features.ipynb` | 5 Feature Views, stream freshness demo, training dataset |
| `02_train.ipynb` | ML Job V1 + Tuner HPO V2, experiment tracking, registry |
| `03_deploy_gateway.ipynb` | SPCS services, Gateway with canary promotion |
| `04_monitor.ipynb` | Inference autocapture, baseline, Model Monitor, drift queries |
| `05_simulator.ipynb` | OFS latency benchmark, single prediction, load test, QPS ramp |

## File Structure

```
setup/
  01_foundations.sql           Database, schemas, synthetic data (~3M applications, ~100 fraud rings)
  02_edge_construction.sql     Dynamic table: applicant edges from ring attributes
  03_spcs_infrastructure.sql   GPU compute pool, image repo, job service, scheduled task
  04_incremental_heuristic.sql COMMUNITY_ASSIGNMENTS table for Leiden writes
spcs/
  Dockerfile                   cuGraph container (nvidia/cuda:12.4.1-runtime + pip cuGraph)
  leiden_job.py                Leiden community detection job with benchmark timing
notebooks/
  00_setup.ipynb               Roles, entities, online service, Leiden trigger
  01_features.ipynb            5 FVs + stream freshness + training dataset generation
  02_train.ipynb               ML Job V1 + Tuner HPO V2 + experiment tracking
  03_deploy_gateway.ipynb      SPCS V1+V2 services, Gateway canary promotion
  04_monitor.ipynb             Autocapture DT, baseline, Model Monitor, drift queries
  05_simulator.ipynb           Latency benchmark, load test, QPS generator
source/
  train.py                     XGBoost training script for ML Jobs (15 features)
  utils.py                     Synthetic data generation utilities
simulator/
  config.py                    Constants, feature lists, endpoints
  ingest.py                    Stream ingest freshness demo
  predict.py                   Single-application scoring via Gateway
  load_test.py                 Concurrent scoring benchmark
  qps_loadgen.py               Multiprocess QPS generator
presentations/
  graph-fraud-detection-demo.html          Slide deck
  graph-fraud-detection-demo-speaker-notes.md  Internal speaker notes
```

## Three Entities, Five Feature Views

The architecture uses three entities to provide community context even for brand-new applicants:

| Entity | Join Key | Feature View | Purpose |
|---|---|---|---|
| APPLICANT | APPLICANT_ID | GRAPH_COMMUNITY_FEATURES | Direct Leiden community membership |
| ADDRESS | ADDRESS_ID | ADDRESS_COMMUNITY_FEATURES | Inherited context for new applicants at known addresses |
| IP_NETWORK | IP_ADDRESS | IP_COMMUNITY_FEATURES | Inherited context for new applicants sharing known IPs |
| APPLICANT | APPLICANT_ID | STREAM_VELOCITY | Real-time application event velocity |
| APPLICANT | APPLICANT_ID | COMBINED_FRAUD_FEATURES | Experimental: assembles 15 raw features from all FVs |

## Key Design Decisions

- **Three entities for coverage**: ADDRESS and IP_NETWORK entities give brand-new applicants inherited community context even before Leiden processes them directly.
- **Model scores raw features**: The scoring path assembles 15 raw features from parallel OFS reads; the XGBoost model learns to combine them. No hand-crafted risk score.
- **Feature Store owns transformations**: No separate DT layer for features. FeatureViews with `refresh_freq` create managed DTs internally. Postgres online store for ~10ms reads.
- **Job Service**: No idle GPU cost. Container starts, runs Leiden, writes results, exits.
- **Gateway canary**: Zero-downtime model upgrades via `ALTER GATEWAY` traffic split. Rollback is a single command.
- **Model Monitor**: PSI drift detection on inference autocapture DT catches distribution shift before it impacts production accuracy.
- **Leiden on GPU**: RAPIDS cuGraph on SPCS. Single-digit seconds for the algorithm; I/O is the bottleneck.
- **ML Jobs**: Training runs on Snowflake compute — no data leaves the platform.

## Cleanup

```sql
DROP DATABASE IF EXISTS GRAPH_FRAUD_DEMO;
DROP WAREHOUSE IF EXISTS GRAPH_FRAUD_WH;
DROP COMPUTE POOL IF EXISTS GRAPH_FRAUD_GPU_POOL;
DROP COMPUTE POOL IF EXISTS GRAPH_FRAUD_INFERENCE_POOL;
DROP COMPUTE POOL IF EXISTS ML_TRAINING_POOL;
```
