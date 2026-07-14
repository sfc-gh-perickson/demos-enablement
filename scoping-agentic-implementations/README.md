# Scoping Agentic Implementations

[View Presentation](https://sfc-gh-perickson.github.io/demos-enablement/scoping-agentic-implementations/presentations/scoping-agentic-implementations.html)

A workshop module that teaches customers how to move from broad AI aspirations ("talk to your data") to scoped, measurable agent specifications with seed evaluation datasets and phased delivery plans.

## Overview

Most agent projects fail not because the technology isn't ready, but because the scope isn't defined. This module provides a structured methodology for:

1. **Persona mapping** — who will use the agent and what do they actually need?
2. **Question taxonomy** — what will users ask, categorized by type, data source, and risk?
3. **Tool selection** — which Snowflake primitives does each question category require?
4. **Agent spec creation** — a contract between business goals and technical implementation
5. **Seed eval generation** — turning PM/tech intuition into a testable evaluation dataset
6. **Observability-driven iteration** — using production signals to refine scope over time
7. **Phased delivery** — shipping narrow, proving value, expanding with eval-gated phases

## Session Formats

| Format | Duration | Content | Audience |
|--------|----------|---------|----------|
| **Overview** | 30 min | Slides 1-6 (funnel through spec template) | Executive / kickoff |
| **Workshop** | 60 min | All slides + 4-activity workshop exercise | Technical leads + PMs |
| **Deep Dive** | Half day | All slides + workshop + live notebook + group discussion | Full project team |

## Prerequisites

- Snowflake account with SYSADMIN (or equivalent) for lab setup
- Warehouse: XS is sufficient (auto-created by setup.sql)
- For the notebook: Python environment with `snowflake-snowpark-python` or Snowsight Notebooks
- Cortex AI enabled on the account (for CORTEX.COMPLETE in eval generation cells)

## Quick Start

```bash
# 1. Run the setup script in your Snowflake account
#    (via Snowsight worksheet, SnowSQL, or Snowflake CLI)
snowsql -f lab/setup.sql

# 2. Open the presentation
open presentations/scoping-agentic-implementations.html

# 3. Run the workshop notebook
#    (in Snowsight Notebooks or local Jupyter)
```

## Module Structure

```
scoping-agentic-implementations/
├── README.md                          # This file
├── presentations/
│   ├── scoping-agentic-implementations.html           # Slide deck
│   └── scoping-agentic-implementations-speaker-notes.md  # Facilitation guide
└── lab/
    ├── setup.sql                      # Creates database, mock data, stubs
    └── scoping-agentic-implementations-lab.ipynb      # Workshop notebook
```

## Facilitation Guide

### Who should be in the room

- **Required:** Product Manager or business stakeholder, Data Analyst or Analytics Engineer, Technical Lead
- **Recommended:** 1-2 actual target users for the agent (dramatically improves question brainstorm quality)

### Workshop flow (60-min format)

| Time | Activity | Output |
|------|----------|--------|
| 0-5 min | Framing: The Scoping Funnel (slides 1-2) | Shared mental model |
| 5-15 min | Activity 1: Persona Mapping | 2-3 persona cards, Phase 1 persona selected |
| 15-30 min | Activity 2: Question Brainstorm | 15-20 categorized questions |
| 30-40 min | Activity 3: Tool Selection + Prerequisite Audit | Tool map with blocker identification |
| 40-55 min | Activity 4: Seed Eval Draft | 10 questions with ground-truth descriptions |
| 55-60 min | Wrap: Phased Delivery + Next Steps | Draft spec document |

### Common facilitation challenges

- **Too broad:** If participants write vague questions ("How is business?"), push for specificity. Ask: "What would you type into the chat box on Monday morning?"
- **Tool-first thinking:** If participants jump to tools before questions, redirect. "Which question from your taxonomy needs this tool?"
- **Perfectionism on ground truth:** Ground truth can be rough. "A correct answer would include X" is sufficient. Precision comes through iteration.
- **"We need everything in Phase 1":** Push back. The funnel's power is forced prioritization. Ask: "If you could only serve ONE persona with ONE question category, which delivers the most value?"

## Agent Spec Template (Standalone)

Copy this template for use outside the workshop:

```
AGENT SPECIFICATION
===================

Agent Name:         [your_agent_name]
Owner:              [team / individual accountable for quality]
Date:               [spec creation date]

PERSONAS SERVED
---------------
Phase 1: [persona name — role, frequency, success signal]
Phase 2: [persona name — role, frequency, success signal]

QUESTION TAXONOMY
-----------------
| Category      | Example                              | Tool          | Phase |
|---------------|--------------------------------------|---------------|-------|
| Lookup        | "What was Q2 revenue?"               | Analyst       | 1     |
| Aggregation   | "Compare YoY growth by region"       | Analyst       | 1     |
| Reasoning     | "Why did NPS drop?"                  | Analyst+Search| 2     |
| Policy        | "What's our return policy?"          | Search        | 2     |
| Out of scope  | "Write me an email"                  | Instructions  | 1     |

TOOLS (Phase 1)
---------------
- Semantic View: [name, tables covered, prerequisite status]
- Agent Instructions: [refusal boundaries defined]

OUT OF SCOPE
------------
- [Explicit list of what the agent will refuse]

SUCCESS METRICS
---------------
Business: [e.g., "80% of users self-serve without filing a ticket"]
Technical:
  - answer_correctness >= [threshold]
  - tool_selection_accuracy >= [threshold]
  - latency P95 < [target ms]
  - cost/interaction < [budget]

EVAL DATASET
------------
Seed: [count] questions ([breakdown by category])
Target: [count] questions by end of Phase 1
Source: [PM intuition / analyst backlog / user interviews]

PHASED DELIVERY
---------------
Phase 1: [scope] → Exit: [criteria]
Phase 2: [scope] → Exit: [criteria]
Phase 3: [scope] → Exit: [criteria]
Phase 4: [scope] → Exit: [criteria]

KNOWN BLOCKERS
--------------
- [Prerequisites not yet met]
- [Data gaps identified]
- [Access/role requirements]
```

## Companion Modules

This module is the "how to scope" — these companions cover "how to implement":

| Module | Covers | When to use |
|--------|--------|-------------|
| [evaluations/](../evaluations/) | GPA framework, LLM-as-Judge, eval datasets, CI/CD gates | After scoping: building and running evaluations |
| [cortex-ai-observability/](../cortex-ai-observability/) | Surface identification, cost attribution, unified views | After deploying: monitoring and iterating |
| [agent_versioning/](../agent_versioning/) | Named versions, aliases, safe promotion | During iteration: version management |
| [agent-routing/](../agent-routing/) | Supervisor pattern, multi-agent orchestration | Phase 3+: multi-persona routing |
| [semantic-view-description/](../semantic-view-description/) | Description quality grading | Phase 1 prerequisite: semantic view quality |
