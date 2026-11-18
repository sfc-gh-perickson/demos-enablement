# Decision Engine Benchmark on Snowpark Container Services

> **Slides:** [View presentation on GitHub Pages](https://sfc-gh-perickson.github.io/demos-enablement/spcs-decision-model/presentations/decision-engines-spcs.html)

Deploy and benchmark multiple typed-decision engines on SPCS, then compare them against Snowflake's built-in AI functions. One Docker image, one generic SQL function, swap engines with an env var.

## Supported Engines

| Engine | Architecture | Size | What it does |
|---|---|---|---|
| [Laya](https://github.com/NandhaKishorM/laya) | ModernBERT encoder | 421M | Non-autoregressive typed decisions in a single forward pass, ~33ms on T4 |
| [openjev](https://huggingface.co/AlexWortega/openjev) 0.8B | Qwen3.5 cross-encoder | 0.8B | NLI-based typed decisions, fastest openjev variant |
| [openjev](https://huggingface.co/AlexWortega/openjev) 2B | Qwen3.5 cross-encoder | 2B | NLI-based typed decisions, balanced |
| [openjev](https://huggingface.co/AlexWortega/openjev) 4B | Qwen3.5 cross-encoder | 4B | NLI-based typed decisions, highest accuracy |
| Snowflake AI_CLASSIFY | Built-in | — | No SPCS needed, serverless |
| Snowflake AI_COMPLETE | Built-in | — | No SPCS needed, serverless |

All engines answer the same three decision primitives:

| Primitive | Output | Use Cases |
|---|---|---|
| **choice** | Winner + probability distribution over named options | Sentiment classification, entity resolution, intent routing |
| **score** | Expected level on an ordered rubric + distribution | Urgency rating, quality scoring |
| **noul** | Calibrated P(true) from 0.0 to 1.0 | Document filtering, spam detection, churn risk |

## Architecture

One Docker image runs either engine. The `DECISION_ENGINE` env var selects which backend starts. The SPCS adapter provides the same interface to Snowflake regardless.

```
┌──────────────────────────────────────────────────────┐
│  SPCS Container (GPU_NV_S — 1x A10G)                │
│                                                      │
│  DECISION_ENGINE=laya      DECISION_ENGINE=openjev   │
│  ┌─────────────────┐       ┌───────────────────────┐ │
│  │ laya-serve      │  OR   │ openjev_server.py     │ │
│  │ :8001           │       │ :8001                 │ │
│  │ /v1/systemone   │       │ /v1/systemone         │ │
│  └────────┬────────┘       └───────────┬───────────┘ │
│           └───────────┬───────────────┘              │
│               ┌───────┴────────┐                     │
│               │ SPCS Adapter   │◄── DECIDE(state,qs) │
│               │ :8080 /predict │                     │
│               └────────────────┘                     │
└──────────────────────────────────────────────────────┘
```

## Prerequisites

- Snowflake account with SPCS enabled
- Docker Desktop installed and running
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (`snow`) installed and authenticated
- ACCOUNTADMIN role (for network rules and external access integrations)
- SYSADMIN role (for compute pools, services, and functions)

## Project Structure

```
spcs-decision-model/
├── Dockerfile              # Multi-engine image (Laya + openjev)
├── deploy.sh               # Build & push to Snowflake image registry
├── README.md
└── spcs/
    ├── entrypoint.sh       # DECISION_ENGINE switch (laya | openjev)
    ├── spcs_adapter.py     # Generic /predict endpoint (SPCS protocol)
    ├── openjev_server.py   # FastAPI wrapper for OpenJev.decide()
    ├── setup.sql           # Infrastructure + DECIDE() function
    └── benchmark.sql       # Labeled test data + comparison queries
```

## Setup

### Step 1: Create Snowflake infrastructure

Run the first part of `spcs/setup.sql` (steps 1-5). This creates:

- **Database/schema**: `DJEV_DEMO.INFERENCE`
- **Image repository**: `DJEV_DEMO.INFERENCE.DJEV_REPO`
- **Warehouse**: `DJEV_WH` (XSMALL)
- **Compute pool**: `DJEV_GPU_POOL` (1x A10G, 22GB VRAM — all engines fit easily)
- **External access integration**: `DJEV_HF_ACCESS` (HuggingFace model downloads)

Note the `repository_url` from:

```sql
SHOW IMAGE REPOSITORIES LIKE 'DJEV_REPO' IN SCHEMA DJEV_DEMO.INFERENCE;
```

### Step 2: Build and push the Docker image

```bash
./deploy.sh <repository_url>
```

One image supports all engines — no rebuild needed to switch.

### Step 3: Create the service

Run the `CREATE SERVICE` block from `spcs/setup.sql`. By default it starts with Laya. To use openjev instead, change the env vars in the service spec before creating:

```yaml
env:
  DECISION_ENGINE: "openjev"
  OPENJEV_CHECKPOINT: "qwen3.5-4b-nli-v5"
```

### Step 4: Wait for READY

```sql
SELECT SYSTEM$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DECISION_SERVICE');
SELECT SYSTEM$GET_SERVICE_LOGS('DJEV_DEMO.INFERENCE.DECISION_SERVICE', 0, 'decision-engine', 50);
```

First boot downloads model weights from HuggingFace (Laya ~800MB, openjev 4B ~8GB). Subsequent starts use the cached volume.

## Usage: The DECIDE() Function

One generic service function handles all use cases. The caller defines the question schema as a VARIANT:

```sql
DECIDE(state VARCHAR, questions VARIANT) RETURNS VARIANT
```

### Sentiment Classification (choice)

```sql
SELECT
    text,
    DECIDE(text, OBJECT_CONSTRUCT(
        'sentiment', OBJECT_CONSTRUCT(
            'type', 'choice',
            'instructions', 'Classify the sentiment of the text.',
            'criteria', OBJECT_CONSTRUCT(
                'positive', 'positive sentiment or emotion',
                'negative', 'negative sentiment or emotion',
                'neutral', 'neutral, factual, or no clear sentiment'
            )
        )
    )) AS result,
    result:sentiment:choice::VARCHAR AS sentiment,
    ROUND(result:sentiment:confidence::FLOAT, 4) AS confidence
FROM my_reviews;
```

### Entity Resolution (choice)

```sql
SELECT
    description,
    DECIDE(description, OBJECT_CONSTRUCT(
        'match', OBJECT_CONSTRUCT(
            'type', 'choice',
            'instructions', 'Which entity best matches this description?',
            'criteria', PARSE_JSON(candidates_json)
        )
    )) AS result,
    result:match:choice::VARCHAR AS best_match
FROM my_entities;
```

### Document Filtering (noul)

```sql
SELECT
    text,
    DECIDE(text, OBJECT_CONSTRUCT(
        'relevant', OBJECT_CONSTRUCT(
            'type', 'noul',
            'instructions', 'Contains financial performance metrics'
        )
    )) AS result,
    ROUND(result:relevant:noul::FLOAT, 4) AS p_relevant
FROM my_documents
ORDER BY p_relevant DESC;
```

### Multi-Question (all in one call)

```sql
SELECT DECIDE(
    ticket_text,
    OBJECT_CONSTRUCT(
        'department', OBJECT_CONSTRUCT(
            'type', 'choice',
            'instructions', 'Which department should handle this?',
            'criteria', OBJECT_CONSTRUCT(
                'billing', 'invoices, payments, refunds',
                'technical', 'bugs, outages, system errors',
                'sales', 'pricing, new contracts'
            )
        ),
        'urgency', OBJECT_CONSTRUCT(
            'type', 'score',
            'instructions', 'How urgent is this?',
            'criteria', ARRAY_CONSTRUCT('not urgent', 'soon', 'critical')
        ),
        'churn_risk', OBJECT_CONSTRUCT(
            'type', 'noul',
            'instructions', 'Does the user threaten to cancel or leave?'
        )
    )
) AS result
FROM support_tickets;
```

## Response Format

The DECIDE() function returns a VARIANT with one key per question name:

**choice:**
```json
{"sentiment": {"type": "choice", "choice": "positive", "confidence": 0.94,
               "probabilities": {"positive": 0.92, "negative": 0.03, "neutral": 0.05}}}
```

**noul:**
```json
{"relevant": {"type": "noul", "noul": 0.94}}
```

**score:**
```json
{"urgency": {"type": "score", "score": 1.84,
             "probabilities": {"0": 0.05, "1": 0.11, "2": 0.84}}}
```

## Benchmarking

`spcs/benchmark.sql` provides labeled test data and comparison queries across engines.

### Workflow

1. Deploy with engine A (e.g., `DECISION_ENGINE=laya`)
2. Run `benchmark.sql` — captures accuracy per use case
3. Redeploy with engine B (e.g., `DECISION_ENGINE=openjev`, `OPENJEV_CHECKPOINT=qwen3.5-4b-nli-v5`)
4. Run `benchmark.sql` again
5. Compare results side-by-side

The benchmark also includes Snowflake AI_CLASSIFY and AI_COMPLETE baselines that run inline with no SPCS service needed.

### Switching Engines

Change the env vars in the service spec and recreate:

```sql
DROP SERVICE IF EXISTS DJEV_DEMO.INFERENCE.DECISION_SERVICE;

-- Then CREATE SERVICE with updated env:
--   DECISION_ENGINE: "openjev"
--   OPENJEV_CHECKPOINT: "qwen3.5-2b-nli-v5"
```

### Engine Configurations

| Config | Env Vars |
|---|---|
| Laya (default) | `DECISION_ENGINE=laya` |
| openjev 0.8B | `DECISION_ENGINE=openjev`, `OPENJEV_CHECKPOINT=qwen3.5-0.8b-nli-v5` |
| openjev 2B | `DECISION_ENGINE=openjev`, `OPENJEV_CHECKPOINT=qwen3.5-2b-nli-v5` |
| openjev 4B | `DECISION_ENGINE=openjev`, `OPENJEV_CHECKPOINT=qwen3.5-4b-nli-v5` |

## GPU Instance Selection

All engines fit on the smallest GPU instance. Laya is 421M params, openjev 4B is ~8GB in BF16.

| Instance | GPU | VRAM | Notes |
|---|---|---|---|
| **`GPU_NV_S`** | **1x A10G** | **22GB** | **Used here — sufficient for all engines** |
| `GPU_L40S_G1_8` | 1x L40S | 44GB | More headroom for larger batch sizes |

```sql
SHOW COMPUTE POOL INSTANCE FAMILIES;
```

## Cost Management

- Compute pool auto-suspends after 10 minutes idle (`AUTO_SUSPEND_SECS = 600`)
- XSMALL warehouse auto-suspends after 60 seconds
- To suspend manually: `ALTER COMPUTE POOL DJEV_GPU_POOL SUSPEND;`
- To tear down:

```sql
DROP SERVICE IF EXISTS DJEV_DEMO.INFERENCE.DECISION_SERVICE;
ALTER COMPUTE POOL DJEV_GPU_POOL STOP ALL;
DROP COMPUTE POOL IF EXISTS DJEV_GPU_POOL;
DROP DATABASE IF EXISTS DJEV_DEMO;
```

## Troubleshooting

**Service stuck in PENDING:**

```sql
DESCRIBE COMPUTE POOL DJEV_GPU_POOL;
SHOW IMAGES IN IMAGE REPOSITORY DJEV_DEMO.INFERENCE.DJEV_REPO;
```

**Container crashes:**

```sql
SELECT SYSTEM$GET_SERVICE_LOGS('DJEV_DEMO.INFERENCE.DECISION_SERVICE', 0, 'decision-engine', 200);
```

**DECIDE() returns errors:** Verify the service is READY and check which engine is running:

```sql
SELECT SYSTEM$GET_SERVICE_STATUS('DJEV_DEMO.INFERENCE.DECISION_SERVICE');
```
