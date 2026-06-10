# Cortex AI Enablement Kit

An internal enablement repository for Snowflake sales engineers and account executives, containing presentations, speaker notes, and hands-on labs focused on Cortex AI features.

---

## Table of Contents

- [Overview](#overview)
- [Modules](#modules)
  - [Cortex Agent Evaluations](#cortex-agent-evaluations)
  - [Cortex Agent Versioning](#cortex-agent-versioning)
  - [Semantic View Description Quality](#semantic-view-description-quality)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Presentation Format](#presentation-format)

---

## Overview

This repository contains three enablement modules covering key Cortex AI topics:

| Module | Audience | Format | Slides |
|--------|----------|--------|--------|
| Agent Evaluations | SEs, Customers | Presentation + Hands-on Lab | [View](https://sfc-gh-perickson.github.io/demos-enablement/evaluations/presentations/evaluating-cortex-agents.html) |
| Agent Versioning | SEs, Customers | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/agent_versioning/presentations/cortex-agent-versioning.html) |
| Semantic View Description Quality | SEs, AEs | Presentation | [View](https://sfc-gh-perickson.github.io/demos-enablement/semantic-view-description/presentations/semantic-view-description-quality.html) |

Each module includes an HTML slide deck and companion speaker notes. The evaluations module also provides a complete hands-on lab with SQL setup and a Jupyter notebook.

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
4. For the evaluations lab, run `evaluations/lab/setup.sql` in your Snowflake account before starting the notebook

---

## Presentation Format

All presentations follow a consistent format:

- **Dark-themed scrolling HTML** with sidebar navigation
- **Snowflake-branded** styling and color palette
- **Paired speaker notes** in Markdown with per-slide talking points, internal context, common audience questions, and reference URLs
