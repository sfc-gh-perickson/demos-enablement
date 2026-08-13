# Cortex AI Enablement Kit

An internal enablement repository for Snowflake sales engineers and account executives, containing presentations, speaker notes, and hands-on labs focused on Cortex AI features.

---

## Table of Contents

- [Overview](#overview)
- [Modules](#modules)
  - [Cortex Agent Evaluations](#cortex-agent-evaluations)
  - [Cortex Agent Versioning](#cortex-agent-versioning)
  - [Semantic View Description Quality](#semantic-view-description-quality)
  - [Many-Model Training](#many-model-training)
  - [Feature Store](#feature-store)
  - [Cortex AI Observability](#cortex-ai-observability)
  - [Cortex Agent Multi-Tenancy](#cortex-agent-multi-tenancy)
  - [Server-Side Agent Routing](#server-side-agent-routing)
  - [PII Redaction](#pii-redaction)
  - [Label Studio on SPCS](#label-studio-on-spcs)
  - [Dynamic Time-Period Metrics](#dynamic-time-period-metrics)
  - [Model Registry](#model-registry)
  - [Scoping Agentic Implementations](#scoping-agentic-implementations)
  - [Cortex Agent Embedded App Context](#cortex-agent-embedded-app-context)
  - [Cortex Agent Document Context](#cortex-agent-document-context)
  - [Cortex Agent Cost Observability](#cortex-agent-cost-observability)
  - [Agent Data Flywheel](#agent-data-flywheel)
  - [Agent Observability & Analysis](#agent-observability--analysis)
  - [Agentic Schema Mapping](#agentic-schema-mapping)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Presentation Format](#presentation-format)

---

## Overview

This repository contains nineteen enablement modules covering key Cortex AI and Snowflake ML topics:

| Module | Audience | Format | Slides |
|--------|----------|--------|--------|
| Agent Evaluations | SEs, Customers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/evaluations/presentations/evaluating-cortex-agents.html) |
| Agent Versioning | SEs, Customers | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent_versioning/presentations/cortex-agent-versioning.html) |
| Semantic View Description Quality | SEs, AEs | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/semantic-view-description/presentations/semantic-view-description-quality.html) |
| Many-Model Training | SEs, Data Scientists, ML Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/many-model-training/presentations/many-model-training.html) |
| Feature Store | SEs, Data Scientists, ML Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/feature-store/presentations/feature-store.html) |
| Cortex AI Observability | SEs, Platform Admins, Finance | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-observability/presentations/cortex-ai-observability.html) |
| Cortex Agent Multi-Tenancy | SEs, Solution Architects | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-multi-tenancy/presentations/cortex-agent-multi-tenancy.html) |
| Server-Side Agent Routing | SEs, Platform Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent-routing/presentations/server-side-agent-routing.html) |
| PII Redaction | SEs, Data Engineers, Compliance | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/pii-redaction/presentations/pii-redaction.html) |
| Label Studio on SPCS | SEs, ML Engineers, Platform Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/label-studio-spcs/presentations/label-studio-spcs.html) |
| Dynamic Time-Period Metrics | SEs, Analytics Engineers, Data Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/dynamic-time-period-metrics/presentations/dynamic-time-period-metrics.html) |
| Model Registry | SEs, Data Scientists, ML Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/model-registry/presentations/model-registry-overview.html) |
| Scoping Agentic Implementations | Customers, SEs, Solution Architects | Presentation + Workshop | [View](https://sfc-gh-perickson.github.io/demos-enablement/scoping-agentic-implementations/presentations/scoping-agentic-implementations.html) |
| Cortex Agent Embedded App Context | SEs, Solution Architects | Presentation + Demo App | [View](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-embedded-app-context/presentations/cortex-agent-embedded-app-context.html) |
| Cortex Agent Document Context | SEs, Platform Engineers | Presentation + Hands-on Lab + React Demo | [View](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-document-context/presentations/cortex-agent-document-context.html) |
| Cortex Agent Cost Observability | SEs, FinOps Admins | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-cost-observability/presentations/cortex-agent-cost-observability.html) |
| Agent Data Flywheel | SEs, AEs, Solution Architects | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent-data-flywheel/presentations/ai-agent-data-flywheel.html) |
| Agent Observability & Analysis | SEs, ML Engineers, Platform Teams | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent_observability_analysis/presentations/agent-observability-analysis.html) |
| Agentic Schema Mapping | SEs, Data Engineers, Customers | Presentation + Demo | [View](https://sfc-gh-perickson.github.io/demos-enablement/agentic-schema-mapping/presentations/schema-mapper-demo.html) |

Each module includes an HTML slide deck and companion speaker notes. The evaluations, many-model-training, feature-store, cortex-ai-observability, cortex-agent-multi-tenancy, and label-studio-spcs modules also provide complete hands-on labs with SQL setup and notebooks.

---

## Modules

### Cortex Agent Evaluations

**Location:** `evaluations/`

Covers how to systematically measure, iterate on, and maintain quality for AI agents built on Snowflake. Based on the GPA (Ground-truth, Predict, Assess) framework.

**Topics covered:**
- The trust problem with AI agents
- Dataset design (happy paths, edge cases, out-of-scope)
- Rubrics, metrics, and LLM-as-a-Judge
- Monitoring vs. evaluation misconceptions
- CI/CD quality gates and production deployment

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/evaluating-cortex-agents.html`](https://sfc-gh-perickson.github.io/demos-enablement/evaluations/presentations/evaluating-cortex-agents.html) | Slide deck |
| `presentations/evaluating-cortex-agents-speaker-notes.md` | Speaker notes |
| `lab/setup.sql` | SQL setup (database, tables, semantic view, search service) |
| `lab/evaluating-cortex-agents-lab.ipynb` | Hands-on lab notebook (30-45 min) |
| `rough_eval_notes.md` | Informal planning notes |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. Run `evaluations/lab/setup.sql` to create the `CMO_EVAL_LAB` database and supporting objects
3. Open `evaluations/lab/evaluating-cortex-agents-lab.ipynb` in Snowflake Notebooks

The lab walks through building a CMO Assistant agent, creating an evaluation dataset, defining metrics, running evaluations, and iterating on the agent.

---

### Cortex Agent Versioning

**Location:** `agent_versioning/`

Covers the full agent versioning lifecycle: the Live/Named/Alias model, version promotion pipelines, CI/CD integration, A/B testing patterns, monitoring, and rollback.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-agent-versioning.html`](https://sfc-gh-perickson.github.io/demos-enablement/agent_versioning/presentations/cortex-agent-versioning.html) | Slide deck (14 slides) |
| `presentations/cortex-agent-versioning-speaker-notes.md` | Speaker notes with internal context |

---

### Semantic View Description Quality

**Location:** `semantic-view-description/`

Teaches a four-criteria grading framework for semantic view descriptions and demonstrates how Cortex Code automates description review.

**Grading criteria:** Preciseness, Conciseness, Non-Circularity, Correctness

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/semantic-view-description-quality.html`](https://sfc-gh-perickson.github.io/demos-enablement/semantic-view-description/presentations/semantic-view-description-quality.html) | Slide deck |
| `presentations/semantic-view-description-quality-speaker-notes.md` | Speaker notes with demo scripts |

---

### Many-Model Training

**Location:** `many-model-training/`

Covers end-to-end Many-Model Training (MMT) on Snowflake — training thousands of specialized models from one pipeline using Feature Store, Model Registry, Experiment Tracking, and AI-powered monitoring. Uses retail demand forecasting as the example domain.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/many-model-training.html`](https://sfc-gh-perickson.github.io/demos-enablement/many-model-training/presentations/many-model-training.html) | Slide deck (14 slides) |
| `presentations/many-model-training-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, synthetic data generation) |
| `lab/many-model-training-lab.ipynb` | Hands-on lab notebook (45-60 min) |
| `lab/poc/` | Python modules for the training pipeline |

#### Lab Prerequisites

1. A Snowflake account with ML features enabled (Feature Store, Model Registry, ML Jobs)
2. Run `many-model-training/lab/setup.sql` to create the `MMT_DEMO` database and generate synthetic data
3. Open `many-model-training/lab/many-model-training-lab.ipynb` in Snowflake Notebooks

The lab walks through Feature Store setup, distributed training of 200 XGBoost models, model registration, inference, champion/challenger experimentation, and agent-powered monitoring.

---

### Feature Store

**Location:** `feature-store/`

Covers the Snowflake Feature Store end-to-end — from entity definition and feature engineering through offline training datasets, online serving with sub-second lookups, and real-time model inference integration. Uses e-commerce personalization (product recommendations) as the example domain.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/feature-store.html`](https://sfc-gh-perickson.github.io/demos-enablement/feature-store/presentations/feature-store.html) | Slide deck (14 slides) |
| `presentations/feature-store-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, synthetic e-commerce data) |
| `lab/feature-store-lab.ipynb` | Hands-on lab notebook (45-60 min) |

#### Lab Prerequisites

1. A Snowflake account with ML features enabled (Feature Store, Model Registry, Online Feature Tables)
2. Run `feature-store/lab/setup.sql` to create the `FEATURE_STORE_DEMO` database and generate synthetic data
3. Open `feature-store/lab/feature-store-lab.ipynb` in Snowflake Notebooks

The lab walks through Feature Store setup, feature view registration, engineered features, training dataset generation, model training, online serving enablement, real-time retrieval, and model inference integration.

---


### Cortex AI Observability

**Location:** `cortex-ai-observability/`

Covers how to identify which Cortex AI surfaces are driving usage (MCP, REST API, CoWork, Agent API, Cortex Code) and how to attribute costs to teams using built-in observability views.

**Topics covered:**
- Multi-surface architecture and the observability landscape
- Surface identification via `interaction_interface` and usage views
- MCP client identification patterns and limitations
- Token-level and tag-based cost attribution
- Resource budgets and governance
- Query-level compute attribution

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-ai-observability.html`](https://sfc-gh-perickson.github.io/demos-enablement/cortex-ai-observability/presentations/cortex-ai-observability.html) | Slide deck (12 slides) |
| `presentations/cortex-ai-observability-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, unified view, simulated data) |
| `lab/cortex-ai-observability-lab.ipynb` | Hands-on lab notebook (30-45 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. IMPORTED PRIVILEGES on the SNOWFLAKE database (ACCOUNTADMIN has this by default)
3. Run `cortex-ai-observability/lab/setup.sql` to create the `OBSERVABILITY_LAB` database
4. Open `cortex-ai-observability/lab/cortex-ai-observability-lab.ipynb` in Snowflake Notebooks

The lab walks through querying real ACCOUNT_USAGE views to identify adoption patterns across Cortex AI surfaces and attribute costs by user, agent, model, and cost center.

---

### Server-Side Agent Routing

**Location:** `agent-routing/`

Covers the server-side agent routing pattern — using a supervisor Cortex Agent to route requests to specialist agents via stored procedure wrappers. Eliminates cross-surface tool-selection variance by centralizing routing logic inside Snowflake.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/server-side-agent-routing.html`](https://sfc-gh-perickson.github.io/demos-enablement/agent-routing/presentations/server-side-agent-routing.html) | Slide deck (10 slides) |
| `presentations/server-side-agent-routing-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup (agents, procedures, supervisor, evaluation data) |
| `lab/server-side-agent-routing-lab.ipynb` | Hands-on lab notebook (30 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex Agents enabled
2. Run `agent-routing/lab/setup.sql` to create the `ROUTING_DEMO` database and all agent objects
3. Open `agent-routing/lab/server-side-agent-routing-lab.ipynb` in Snowflake Notebooks

The lab walks through testing routing, running evaluations with `tool_selection_accuracy`, inspecting results, and iterating on orchestration instructions.

---

### PII Redaction

**Location:** `pii-redaction/`

Covers three approaches to PII redaction on Snowflake — AI_REDACT (managed), AI_COMPLETE Extract+Replace (custom), and pre-computed caching (sub-second). Includes a head-to-head comparison and decision framework.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/pii-redaction.html`](https://sfc-gh-perickson.github.io/demos-enablement/pii-redaction/presentations/pii-redaction.html) | Slide deck (12 slides) |
| `presentations/pii-redaction-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup (database, synthetic PII data, UDF, cache table) |
| `lab/pii-redaction-lab.ipynb` | Hands-on lab notebook (30-45 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. Run `pii-redaction/lab/setup.sql` to create the `PII_REDACTION_DEMO` database and synthetic data
3. Open `pii-redaction/lab/pii-redaction-lab.ipynb` in Snowflake Notebooks

The lab walks through AI_REDACT (detect/redact modes), AI_COMPLETE extract+replace with structured output, a head-to-head comparison, and building a pre-computed PII cache for sub-second response.

---

### Cortex Agent Multi-Tenancy

**Location:** `cortex-agent-multi-tenancy/`

Covers how to implement row-level and column-level access control for thousands of external users without Snowflake accounts through a single Cortex Agent using session attributes, row access policies, and masking policies.

**Topics covered:**
- Multi-tenancy architecture with immutable session attributes
- Row access policies with SYS_CONTEXT for per-tenant filtering
- Column masking policies with secure UDF patterns
- Entitlements table as the RBAC control plane
- Zero-DDL user management (INSERT/UPDATE/DELETE)
- Cortex Search limitations and workarounds

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-agent-multi-tenancy.html`](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-multi-tenancy/presentations/cortex-agent-multi-tenancy.html) | Slide deck (12 slides) |
| `presentations/cortex-agent-multi-tenancy-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, tables, policies, agent) |
| `lab/cortex-agent-multi-tenancy-lab.ipynb` | Hands-on lab notebook (30-45 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE ROW ACCESS POLICY privileges
3. Run `cortex-agent-multi-tenancy/lab/setup.sql` to create the `MULTI_TENANCY_LAB` database
4. Open `cortex-agent-multi-tenancy/lab/cortex-agent-multi-tenancy-lab.ipynb` in Snowflake Notebooks

The lab walks through building a multi-tenant sales analytics agent, applying row/column policies, testing isolation across tenants, and demonstrating zero-DDL user onboarding.

---

### Label Studio on SPCS

**Location:** `label-studio-spcs/`

Covers deploying Label Studio, an open-source data labeling platform, on Snowpark Container Services with Snowflake Postgres as the managed database backend. Demonstrates running containerized web applications on SPCS with persistent storage and public endpoints.

**Topics covered:**
- SPCS service deployment with custom Docker images
- Snowflake Postgres as an application database
- Stage volumes for data access
- Public endpoints with OAuth authentication
- Data labeling workflow with Snowflake-native data

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/label-studio-spcs.html`](https://sfc-gh-perickson.github.io/demos-enablement/label-studio-spcs/presentations/label-studio-spcs.html) | Slide deck (11 slides) |
| `presentations/label-studio-spcs-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, Postgres instance, compute pool, sample data) |
| `lab/Dockerfile` | Container image for Label Studio |
| `lab/label-studio-spec.yaml` | SPCS service specification |
| `lab/label-studio-spcs-lab.ipynb` | Hands-on lab notebook (30-45 min) |

#### Lab Prerequisites

1. A Snowflake account with SPCS and Snowflake Postgres enabled
2. A role with CREATE DATABASE, CREATE WAREHOUSE, CREATE COMPUTE POOL, CREATE POSTGRES INSTANCE privileges
3. Docker installed locally for building and pushing the container image
4. Run `label-studio-spcs/lab/setup.sql` to create the `LABEL_STUDIO_SPCS` database and all infrastructure
5. Open `label-studio-spcs/lab/label-studio-spcs-lab.ipynb` in Snowflake Notebooks

The lab walks through building the container image, deploying Label Studio on SPCS, creating annotation projects, labeling data, and comparing human labels with Cortex AI classification.

---

### Dynamic Time-Period Metrics

**Location:** `dynamic-time-period-metrics/`

Demonstrates how to define metrics that calculate dynamically over adjustable time periods (monthly, quarterly, yearly) in Snowflake semantic views using variables, window function metrics, and combined patterns.

**Topics covered:**
- Variables for query-time grain switching (month/quarter/year)
- Window function metrics (rolling averages, LAG, running totals)
- `PARTITION BY EXCLUDING` for adaptive window partitioning
- Combined pattern: multiple grain dimensions + window functions
- Known limitations and workarounds

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/dynamic-time-period-metrics.html`](https://sfc-gh-perickson.github.io/demos-enablement/dynamic-time-period-metrics/presentations/dynamic-time-period-metrics.html) | Slide deck (12 slides) |
| `presentations/dynamic-time-period-metrics-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, sample data, 3 semantic views) |
| `lab/dynamic-time-period-metrics-lab.ipynb` | Hands-on lab notebook (20-30 min) |

#### Lab Prerequisites

1. A Snowflake account with semantic views enabled
2. A role with CREATE DATABASE and CREATE WAREHOUSE privileges
3. Run `dynamic-time-period-metrics/lab/setup.sql` to create the `DYNAMIC_METRICS_DEMO` database
4. Open `dynamic-time-period-metrics/lab/dynamic-time-period-metrics-lab.ipynb` in Snowflake Notebooks

The lab walks through three patterns for dynamic time-period metrics: variable-based grain switching, window function metrics for rolling/comparative calcs, and a combined approach with multiple grain dimensions.

---

### Model Registry

**Location:** `model-registry/`

Demonstrates uploading a pre-trained model artifact (XGBoost pickle) to Snowflake's Model Registry and running inference directly in Snowflake without moving data out.

**Topics covered:**
- Training and serializing an XGBoost model locally
- Connecting to Snowflake and creating a registry schema
- Registering a model with `snowflake-ml-python`
- Running serverless inference via the registered model version
- Version management and model exploration

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/model-registry-overview.html`](https://sfc-gh-perickson.github.io/demos-enablement/model-registry/presentations/model-registry-overview.html) | Slide deck (7 slides) |
| `train_model.py` | Train XGBoost classifier and save as pickle |
| `register_model.ipynb` | Hands-on notebook: schema setup, registration, inference |
| `requirements.txt` | Python dependencies |

#### Lab Prerequisites

1. A Snowflake account with ML features enabled (Model Registry)
2. Python environment with `pip install -r model-registry/requirements.txt`
3. Run `python model-registry/train_model.py` to generate the model artifact
4. Open `model-registry/register_model.ipynb` and fill in connection parameters

The notebook creates the `ML_REGISTRY_DEMO.REGISTRY` schema, loads the pickle, registers it, and runs inference end to end.

---

### Scoping Agentic Implementations

**Location:** `scoping-agentic-implementations/`

A customer-facing workshop that teaches how to scope agentic AI implementations using a structured discovery process — moving from broad business aspirations through persona mapping, question taxonomy, tool selection, and seed evaluation generation to a completed agent specification with phased delivery plan.

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/scoping-agentic-implementations.html`](https://sfc-gh-perickson.github.io/demos-enablement/scoping-agentic-implementations/presentations/scoping-agentic-implementations.html) | Slide deck (12 slides) |
| `presentations/scoping-agentic-implementations-speaker-notes.md` | Speaker notes with facilitation guidance |
| `lab/setup.sql` | SQL setup script (database, mock observability data, sample tables) |
| `lab/scoping-agentic-implementations-lab.ipynb` | Workshop notebook (60 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. Run `scoping-agentic-implementations/lab/setup.sql` to create the `SCOPING_LAB` database
3. Open `scoping-agentic-implementations/lab/scoping-agentic-implementations-lab.ipynb` in Snowflake Notebooks

The workshop guides participants through persona mapping, question taxonomy creation, tool selection, and seed eval generation for their own use case.

---

### Cortex Agent Embedded App Context

**Location:** `cortex-agent-embedded-app-context/`

Demonstrates how to scope Cortex Agent responses to the user's current application context by injecting page state into a system message when calling a named agent object. The agent sees what the user sees and tailors its answers accordingly.

**Topics covered:**
- Named agent objects (CREATE AGENT with pre-configured tools)
- Context injection via system messages in the messages array
- Persona-based response scoping
- Streamlit-in-Snowflake deployment with `_snowflake.send_snow_api_request()`

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-agent-embedded-app-context.html`](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-embedded-app-context/presentations/cortex-agent-embedded-app-context.html) | Slide deck |
| `setup.sql` | SQL setup (tables, semantic view, agent object) |
| `snowflake.yml` | SiS deployment manifest |
| `app.py` | Streamlit app with 3 dashboard pages + persona selector |
| `agent_client.py` | REST API client (SiS + local PAT) |
| `demo_notebook.ipynb` | Step-by-step walkthrough notebook |

#### Prerequisites

1. A Snowflake account with Cortex Agents enabled
2. Run `cortex-agent-embedded-app-context/setup.sql` to create the `CORTEX_AGENT_DEMO` database
3. Run locally with `streamlit run app.py` or deploy with `snow streamlit deploy --replace`

---

### Cortex Agent Document Context

**Location:** `cortex-agent-document-context/`

Covers how to enable file/document uploads in a custom frontend calling the Cortex Agent REST API. Teaches the recommended architecture pattern: a backend that stages files + a UDF tool the agent uses to read them on demand via AI_PARSE_DOCUMENT.

**Topics covered:**
- Why file upload is not natively supported in agent:run (content type limitations)
- Architecture: backend uploads to stage, agent reads via UDF tool
- AI_PARSE_DOCUMENT for PDF/DOCX/PPTX/TXT/HTML
- File type handling (rename .csv/.json to .txt for compatibility)
- Multi-turn threaded conversations with document context
- Production considerations (caching, security, context window limits)

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-agent-document-context.html`](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-document-context/presentations/cortex-agent-document-context.html) | Slide deck (9 slides) |
| `presentations/cortex-agent-document-context-speaker-notes.md` | Speaker notes with internal context |
| `lab/setup.sql` | SQL setup script (database, stage, UDF, semantic view, agent) |
| `lab/cortex-agent-document-context-lab.ipynb` | Hands-on lab notebook (30 min) |
| `lab/backend.py` | Flask backend for file upload to stage |
| `lab/biteiq-chat-demo.html` | Single-file React chat app demo |
| `lab/sample-docs/` | Sample files (TXT, CSV, PDF) for testing |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled (AI_PARSE_DOCUMENT, Cortex Agents)
2. Cross-region inference enabled for agent LLM calls
3. Run `cortex-agent-document-context/lab/setup.sql` to create the `DOCUMENT_CONTEXT_LAB` database
4. For the React demo: `pip install flask flask-cors` and run `python backend.py`

The lab walks through uploading documents to stage, testing the UDF tool directly, calling the agent with file hints, multi-turn threaded conversations, and running the full React + backend demo.

---

### Cortex Agent Cost Observability

**Location:** `cortex-agent-cost-observability/`

Covers how to understand and manage the cost of Cortex Agent deployments using ACCOUNT_USAGE views. Answers: how many tokens are consumed, by whom, how much do Analyst tool calls cost, and what warehouse compute is triggered.

**Topics covered:**
- CORTEX_AGENT_USAGE_HISTORY for per-request token and credit consumption
- Per-model token breakdown with cache hit ratios
- CORTEX_ANALYST_USAGE_HISTORY for Analyst tool credits
- QUERY_ATTRIBUTION_HISTORY for warehouse compute attribution
- Total cost per request (tokens + compute)
- Resource budgets for governance

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/cortex-agent-cost-observability.html`](https://sfc-gh-perickson.github.io/demos-enablement/cortex-agent-cost-observability/presentations/cortex-agent-cost-observability.html) | Slide deck |
| `lab/setup.sql` | SQL setup script (database, simulated fallback data) |
| `lab/cortex-agent-cost-observability-lab.ipynb` | Hands-on lab notebook (30 min) |

#### Lab Prerequisites

1. A Snowflake account (ACCOUNTADMIN or role with ACCOUNT_USAGE access)
2. Run `cortex-agent-cost-observability/lab/setup.sql` to create the `AGENT_COST_LAB` database
3. Open `cortex-agent-cost-observability/lab/cortex-agent-cost-observability-lab.ipynb`

The lab queries real ACCOUNT_USAGE views (with simulated fallback data) to analyze token consumption, per-user attribution, Analyst credits, warehouse compute, and daily cost trends.

---

### Agent Data Flywheel

**Location:** `agent-data-flywheel/`

Covers the strategic narrative of how Snowflake's converged data architecture enables a compounding improvement loop for AI agents — business data, observability data, and evaluation data in one governed platform.

**Topics covered:**
- The strategic problem with fragmented agent stacks
- Three data pillars (business, evaluation, observability)
- The flywheel cycle: Deploy → Observe → Mine → Evaluate → Improve → Redeploy
- Improvement levers (instructions, verified queries, search corpus, fine-tuning, custom tools)
- Competitive differentiation vs. hyperscaler agent platforms

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/ai-agent-data-flywheel.html`](https://sfc-gh-perickson.github.io/demos-enablement/agent-data-flywheel/presentations/ai-agent-data-flywheel.html) | Slide deck (10 slides) |
| `presentations/ai-agent-data-flywheel-speaker-notes.md` | Speaker notes with internal context |

---

### Agent Observability & Analysis

**Location:** `agent_observability_analysis/`

Demonstrates the technical implementation of the Agent Data Flywheel — mining production observability data to build evaluation datasets that test an agent on its actual failure modes. Uses a CMO Assistant agent (Cortex Analyst + Cortex Search) as the example.

**Topics covered:**
- Observability events schema (`GET_AI_OBSERVABILITY_EVENTS`)
- Three signal mining techniques: explicit feedback, implicit rephrase detection, intent classification
- Two-step rephrase detection (embedding similarity + LLM confirmation)
- Evaluation dataset assembly with auto-generated ground truth
- Running `EXECUTE_AI_EVALUATION` against mined datasets
- Issue classification and improvement lever mapping

**Contents:**

| File | Description |
|------|-------------|
| [`presentations/agent-observability-analysis.html`](https://sfc-gh-perickson.github.io/demos-enablement/agent_observability_analysis/presentations/agent-observability-analysis.html) | Slide deck (12 slides) |
| `presentations/agent-observability-analysis-speaker-notes.md` | Speaker notes with internal context |
| `observability-to-evals.ipynb` | Hands-on lab notebook (45-60 min) |

#### Lab Prerequisites

1. A Snowflake account with Cortex AI features enabled
2. `SNOWFLAKE.CORTEX_USER` database role granted
3. `READ UNREDACTED AI OBSERVABILITY EVENTS TABLE` privilege (for feedback text)
4. Cross-region inference enabled
5. Run `setup.sql` (if present) to create the `CMO_EVAL_LAB` database, or follow notebook Section 1

The notebook walks through creating a demo agent, simulating production traffic via REST API, submitting feedback, detecting rephrases in threaded conversations, mining all three signal types from observability, assembling an eval dataset, and running evaluations.

---

### Agentic Schema Mapping

**Location:** `agentic-schema-mapping/`

An all-in-Snowflake pipeline that maps messy CSV data into canonical financial table schemas. A Cortex Agent orchestrates the workflow via Snowflake CoWork, using custom tools (stored procedures/UDFs) for profiling, AI-powered mapping proposals, entity resolution, and deterministic COPY INTO execution.

**Topics covered:**
- Cortex Agent with 6 custom tools (generic type backed by UDFs/procedures)
- AI-powered column mapping with caching (SHA256 hash of column signatures)
- Entity resolution via LLM with value-level caching
- Deterministic SQL builder (no LLM writes SQL — COPY INTO is constructed from an operations enum)
- Semantic view for querying loaded data via Cortex Analyst

**Contents:**

| File | Description |
|------|-------------|
| File | Description |
|------|-------------|
| [`presentations/schema-mapper-demo.html`](https://sfc-gh-perickson.github.io/demos-enablement/agentic-schema-mapping/presentations/schema-mapper-demo.html) | Slide deck |
| `presentations/schema-mapper-speaker-notes.md` | Speaker notes |
| `setup.sql` | DDL for database, schemas, stage, canonical tables, config tables, reference tables |
| `seed_reference_data.sql` | Reference data (departments, GL accounts, vendors, expense categories, etc.) |
| `deploy.sql` | All UDFs, stored procedures, and the Cortex Agent |
| `semantic_view.yaml` | Semantic view definition for Cortex Analyst |
| `data/` | Sample data at 3 quality tiers (clean, messy, chaotic) |

#### Deployment

1. Run `setup.sql` to create the `ACME_FINANCE` database and all objects
2. Run `seed_reference_data.sql` to populate reference tables
3. Run `deploy.sql` to deploy UDFs, procedures, and the agent
4. Upload CSVs to `@ACME_FINANCE.INGESTION.UPLOAD_STAGE`
5. Open Snowflake CoWork, select **Schema Mapper Agent**, and say "Map my expense file"

---

## Repository Structure

```
enablement/
├── README.md
├── agent-routing/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── server-side-agent-routing-lab.ipynb
│   └── presentations/
│       ├── server-side-agent-routing.html
│       └── server-side-agent-routing-speaker-notes.md
├── agentic-schema-mapping/
│   ├── setup.sql
│   ├── seed_reference_data.sql
│   ├── deploy.sql
│   ├── semantic_view.yaml
│   ├── data/
│   └── presentations/
│       ├── schema-mapper-demo.html
│       └── schema-mapper-speaker-notes.md
├── agent-data-flywheel/
│   └── presentations/
│       ├── ai-agent-data-flywheel.html
│       └── ai-agent-data-flywheel-speaker-notes.md
├── agent_observability_analysis/
│   ├── observability-to-evals.ipynb
│   └── presentations/
│       ├── agent-observability-analysis.html
│       └── agent-observability-analysis-speaker-notes.md
├── cortex-agent-cost-observability/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── cortex-agent-cost-observability-lab.ipynb
│   └── presentations/
│       └── cortex-agent-cost-observability.html
├── cortex-agent-embedded-app-context/
│   ├── setup.sql
│   ├── snowflake.yml
│   ├── app.py
│   ├── agent_client.py
│   ├── demo_notebook.ipynb
│   └── presentations/
│       └── cortex-agent-embedded-app-context.html
├── cortex-agent-document-context/
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── cortex-agent-document-context-lab.ipynb
│   │   ├── backend.py
│   │   ├── biteiq-chat-demo.html
│   │   └── sample-docs/
│   └── presentations/
│       ├── cortex-agent-document-context.html
│       └── cortex-agent-document-context-speaker-notes.md
├── cortex-agent-multi-tenancy/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── cortex-agent-multi-tenancy-lab.ipynb
│   └── presentations/
│       ├── cortex-agent-multi-tenancy.html
│       └── cortex-agent-multi-tenancy-speaker-notes.md
├── cortex-ai-observability/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── cortex-ai-observability-lab.ipynb
│   └── presentations/
│       ├── cortex-ai-observability.html
│       └── cortex-ai-observability-speaker-notes.md
├── agent_versioning/
│   └── presentations/
│       ├── cortex-agent-versioning.html
│       └── cortex-agent-versioning-speaker-notes.md
├── dynamic-time-period-metrics/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── dynamic-time-period-metrics-lab.ipynb
│   └── presentations/
│       ├── dynamic-time-period-metrics.html
│       └── dynamic-time-period-metrics-speaker-notes.md
├── evaluations/
│   ├── rough_eval_notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   └── evaluating-cortex-agents-lab.ipynb
│   └── presentations/
│       ├── evaluating-cortex-agents.html
│       └── evaluating-cortex-agents-speaker-notes.md
├── label-studio-spcs/
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── Dockerfile
│   │   ├── label-studio-spec.yaml
│   │   └── label-studio-spcs-lab.ipynb
│   └── presentations/
│       ├── label-studio-spcs.html
│       └── label-studio-spcs-speaker-notes.md
├── feature-store/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── feature-store-lab.ipynb
│   └── presentations/
│       ├── feature-store.html
│       └── feature-store-speaker-notes.md
├── many-model-training/
│   ├── lab/
│   │   ├── setup.sql
│   │   ├── many-model-training-lab.ipynb
│   │   └── poc/
│   │       ├── config.yaml
│   │       ├── utils.py
│   │       ├── feature_store.py
│   │       ├── train.py
│   │       ├── register.py
│   │       ├── infer.py
│   │       ├── experiment.py
│   │       └── agent_monitor.py
│   └── presentations/
│       ├── many-model-training.html
│       └── many-model-training-speaker-notes.md
├── model-registry/
│   ├── train_model.py
│   ├── register_model.ipynb
│   ├── requirements.txt
│   └── presentations/
│       └── model-registry-overview.html
└── semantic-view-description/
    └── presentations/
        ├── semantic-view-description-quality.html
        └── semantic-view-description-quality-speaker-notes.md
├── scoping-agentic-implementations/
│   ├── lab/
│   │   ├── setup.sql
│   │   └── scoping-agentic-implementations-lab.ipynb
│   └── presentations/
│       ├── scoping-agentic-implementations.html
│       └── scoping-agentic-implementations-speaker-notes.md
```

---

## Getting Started

1. Clone this repository
2. Open any `.html` presentation file in a browser to view slides
3. Reference the corresponding `-speaker-notes.md` file for talking points
4. For hands-on labs:
   - **Evaluations:** Run `evaluations/lab/setup.sql` before starting the notebook
   - **Many-Model Training:** Run `many-model-training/lab/setup.sql` before starting the notebook
   - **Cortex AI Observability:** Run `cortex-ai-observability/lab/setup.sql` before starting the notebook
   - **Cortex Agent Multi-Tenancy:** Run `cortex-agent-multi-tenancy/lab/setup.sql` before starting the notebook
   - **Agent Routing:** Run `agent-routing/lab/setup.sql` before starting the notebook
   - **PII Redaction:** Run `pii-redaction/lab/setup.sql` before starting the notebook
   - **Label Studio on SPCS:** Run `label-studio-spcs/lab/setup.sql` before starting the notebook
   - **Dynamic Time-Period Metrics:** Run `dynamic-time-period-metrics/lab/setup.sql` before starting the notebook
   - **Model Registry:** Run `python model-registry/train_model.py` then open `model-registry/register_model.ipynb`
   - **Scoping Agentic Implementations:** Run `scoping-agentic-implementations/lab/setup.sql` before starting the notebook
   - **Cortex Agent Embedded App Context:** Run `cortex-agent-embedded-app-context/setup.sql`, then `streamlit run app.py` or `snow streamlit deploy --replace`
   - **Cortex Agent Document Context:** Run `cortex-agent-document-context/lab/setup.sql`, then optionally `python lab/backend.py` for the React demo
   - **Cortex Agent Cost Observability:** Run `cortex-agent-cost-observability/lab/setup.sql` before starting the notebook
   - **Agent Observability & Analysis:** Follow notebook Section 1 in `agent_observability_analysis/observability-to-evals.ipynb` (self-contained setup)
   - **Agentic Schema Mapping:** Run `setup.sql`, `seed_reference_data.sql`, then `deploy.sql` in the `agentic-schema-mapping/` directory

---

## Presentation Format

All presentations follow a consistent format:

- **Dark-themed scrolling HTML** with sidebar navigation
- **Snowflake-branded** styling and color palette
- **Paired speaker notes** in Markdown with per-slide talking points, internal context, common audience questions, and reference URLs
