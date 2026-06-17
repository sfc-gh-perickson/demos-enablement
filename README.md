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
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Presentation Format](#presentation-format)

---

## Overview

This repository contains four enablement modules covering key Cortex AI and Snowflake ML topics:

| Module | Audience | Format | Slides |
|--------|----------|--------|--------|
| Agent Evaluations | SEs, Customers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/evaluations/presentations/evaluating-cortex-agents.html) |
| Agent Versioning | SEs, Customers | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent_versioning/presentations/cortex-agent-versioning.html) |
| Semantic View Description Quality | SEs, AEs | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/semantic-view-description/presentations/semantic-view-description-quality.html) |
| Many-Model Training | SEs, Data Scientists, ML Engineers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/many-model-training/presentations/many-model-training.html) |

Each module includes an HTML slide deck and companion speaker notes. The evaluations and many-model-training modules also provide complete hands-on labs with SQL setup and notebooks.

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

## Repository Structure

```
enablement/
├── README.md
├── agent_versioning/
│   └── presentations/
│       ├── cortex-agent-versioning.html
│       └── cortex-agent-versioning-speaker-notes.md
├── evaluations/
│   ├── rough_eval_notes.md
│   ├── lab/
│   │   ├── setup.sql
│   │   └── evaluating-cortex-agents-lab.ipynb
│   └── presentations/
│       ├── evaluating-cortex-agents.html
│       └── evaluating-cortex-agents-speaker-notes.md
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
└── semantic-view-description/
    └── presentations/
        ├── semantic-view-description-quality.html
        └── semantic-view-description-quality-speaker-notes.md
```

---

## Getting Started

1. Clone this repository
2. Open any `.html` presentation file in a browser to view slides
3. Reference the corresponding `-speaker-notes.md` file for talking points
4. For hands-on labs:
   - **Evaluations:** Run `evaluations/lab/setup.sql` before starting the notebook
   - **Many-Model Training:** Run `many-model-training/lab/setup.sql` before starting the notebook

---

## Presentation Format

All presentations follow a consistent format:

- **Dark-themed scrolling HTML** with sidebar navigation
- **Snowflake-branded** styling and color palette
- **Paired speaker notes** in Markdown with per-slide talking points, internal context, common audience questions, and reference URLs
