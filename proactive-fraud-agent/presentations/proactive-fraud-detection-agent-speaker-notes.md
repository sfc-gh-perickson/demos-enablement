# Proactive Fraud Detection Agent — Speaker Notes

## Account Context

This presentation demonstrates Snowflake as the complete platform for proactive fraud detection — replacing fragmented stacks of external ML infrastructure, custom alerting systems, and reactive investigation tools. The customer's current architecture has a "Sidekick" that only works after Step 4 (when a human already pulled up a case). This demo shows how Snowflake can shift intelligence to Steps 1-3: detecting, explaining, and investigating fraud before anyone goes looking. The key products showcased: Dynamic Tables, Feature Store, Snowpark ML (XGBoost), Model Registry, Cortex Agent with DATA_AGENT_RUN, and Snowflake App Runtime (SAR/SPCS).

---

## Slide: Overview (Hero)

**Talking Points:**
- Open with the business outcome: "What if fraud investigations started themselves?"
- The four stats anchor the value props: scale (500K txns), explainability (SHAP), speed (5 min), and human-in-the-loop (thread continuity)
- Emphasize "Snowflake-native" — no external ML serving, no separate app hosting, no integration tax

**Internal Context:**
- This demo is synthetic but designed to be swapped 1:1 with real data. The fraud patterns are realistic enough to produce meaningful model outputs.
- The 5-minute latency is the Dynamic Table TARGET_LAG — could go to 1 minute but that's the minimum supported today.

---

## Slide: The Problem

**Talking Points:**
- Walk through the customer's current workflow on the left — emphasize that "Sidekick sits after Step 4"
- The right column shows the shift: the agent is in the pipeline, not bolted on after
- The highlight box is the key message: proactive vs reactive

**Internal Context:**
- The customer's current architecture has separate products (Secure, Engage, Incident) each with their own data flows. The "Data Intelligence" layer does identity resolution but doesn't score or investigate.
- Their risk dictionary is embedded in C# application code — we're showing how to externalize it into ML + agent reasoning.

---

## Slide: Architecture

**Talking Points:**
- Walk the flow top-to-bottom: raw data → dynamic tables → feature store → ML → priorities → agent → reports → portal
- Call out that everything in blue/green/purple boxes is a Snowflake-native object
- "No external infrastructure" is the competitive differentiator vs. Databricks/SageMaker stacks

**References:**
- Dynamic Tables: https://docs.snowflake.com/en/user-guide/dynamic-tables-about
- Feature Store: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview
- Cortex Agent: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agent
- Snowflake App Runtime: https://docs.snowflake.com/en/developer-guide/snowflake-apps/about-apps

---

## Slide: Pipeline Stages

**Talking Points:**
- This is the "6 scripts, run in order" story. Emphasize simplicity.
- Stage 1-2 are data engineering (SQL only)
- Stage 3 is the bridge to ML (Python SDK)
- Stage 4 is the ML core
- Stage 5-6 are the "proactive" differentiator

**Internal Context:**
- If they ask "why not use ANOMALY_DETECTION built-in?" — it's time-series-oriented and doesn't give SHAP explanations. XGBoost is more appropriate for tabular fraud features and gives full explainability.
- Feature Store SDK creates Dynamic Tables under the hood for managed refresh. Don't say this unprompted — it can confuse the message.

---

## Slide: Feature Store

**Talking Points:**
- Single entity (CUSTOMER), single feature view — deliberately simple
- The table shows the actual features: velocity, amount, behavioral, temporal, derived
- Emphasize "managed refresh" — features stay fresh without cron jobs or Airflow

**References:**
- Feature Store overview: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/overview
- Feature Views: https://docs.snowflake.com/en/developer-guide/snowflake-ml/feature-store/feature-views

**Internal Context:**
- Feature Store is GA. The refresh_freq creates a Dynamic Table behind the scenes.
- If asked about online serving (low-latency lookups): available but requires a Postgres-backed service. Not relevant for this batch scoring demo.

---

## Slide: XGBoost + SHAP

**Talking Points:**
- Show the three panels: training, explainability, registry
- SHAP is the "why" — every customer gets a personalized explanation
- The code example shows what SHAP output looks like — this powers the waterfall chart in the portal
- Model Registry means governance: versioning, lineage, rollback

**References:**
- Snowpark ML XGBoost: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/built-in-models/snowpark-ml
- Model Registry: https://docs.snowflake.com/en/developer-guide/snowflake-ml/model-registry/overview

**Internal Context:**
- SHAP computation happens client-side in the Python script (pulls data down, runs TreeExplainer, pushes results back). For production, this could be a stored procedure on a Snowpark-optimized warehouse.
- If they ask about GPU training: Snowpark ML XGBoost runs on CPU. For GPU, they'd need a compute pool — overkill for this tabular dataset.

---

## Slide: Cortex Agent

**Talking Points:**
- Walk the flow: priorities in → agent runs → reports out
- DATA_AGENT_RUN with create_thread=TRUE is the key API call
- The agent has a Cortex Analyst tool (can query the data) and produces structured output
- 5-minute task schedule means new priorities are investigated within minutes

**References:**
- DATA_AGENT_RUN: https://docs.snowflake.com/en/sql-reference/functions/data_agent_run-snowflake-cortex
- CREATE AGENT: https://docs.snowflake.com/en/sql-reference/sql/create-agent
- Snowflake Tasks: https://docs.snowflake.com/en/user-guide/tasks-intro

**Internal Context:**
- DATA_AGENT_RUN is the SQL wrapper around the Agent REST API. The TRUE parameter creates a thread automatically.
- Thread_id comes back in the response metadata. This is what enables conversation pickup.
- Token cost: each investigation is ~2-4K tokens. At 100 priorities/day, cost is negligible.
- If they ask about streaming agents: not supported today. Batch via Task is the pattern.

---

## Slide: Investigation Portal

**Talking Points:**
- Four panels = four components of the React app
- SHAP waterfall is the "wow" visual — shows exactly which features drove the score
- Chat panel is the differentiator: analyst doesn't start from scratch
- Deployed via SAR (Snowflake App Runtime) — runs on SPCS with native auth

**References:**
- Snowflake App Runtime: https://docs.snowflake.com/en/developer-guide/snowflake-apps/about-apps
- SAR deployment: https://docs.snowflake.com/en/developer-guide/snowflake-apps/create-deploy-app

**Internal Context:**
- SAR is the new name for Snowflake Apps on SPCS. Uses `snow app deploy`. Next.js runs in a container.
- Auth is handled natively by SAR — no OAuth setup needed. The app runs as the logged-in Snowflake user.
- Recharts library handles the SHAP waterfall chart — lightweight, works well in Next.js.

---

## Slide: Thread Continuity

**Talking Points:**
- This is the slide that explains "why thread_id matters"
- Walk through the 4-step flow slowly — this is the novel architecture
- The user experience example at the bottom is the demo moment: show an analyst asking a follow-up question and the agent already knowing the context

**Internal Context:**
- thread_id is returned in the response metadata from DATA_AGENT_RUN when create_thread=TRUE
- For subsequent calls, you pass thread_id in the request body and the agent has full prior context
- This is a significant UX improvement over stateless LLM calls (COMPLETE) which have no memory
- If they ask "what about CoWork?": CoWork uses threads too, but the React portal gives custom UX control. Both patterns work.

---

## Slide: Before vs After

**Talking Points:**
- Walk the table row by row — each row is a "dimension of improvement"
- Detection: rules → ML
- Investigation: human-initiated → agent-initiated
- Explainability: rule name → per-customer SHAP
- Context: from scratch → thread continuity
- Latency: hours → minutes
- Infrastructure: multi-stack → single platform

**Internal Context:**
- The "100% Snowflake-native" claim is accurate for this demo. In production they'd still need Snowpipe/Streaming for ingestion from their source systems.
- Competitive positioning: Databricks can do the ML piece but not the agent + app in one platform. AWS requires SageMaker + Lambda + separate app hosting.

---

## Slide: Demo Flow

**Talking Points:**
- Frame as "I'm going to show you this working end-to-end in 15 minutes"
- The portal demo (5 min) is the climax — save it for last
- If time is short, skip the ML training step and pre-run it

---

## Slide: Next Steps

**Talking Points:**
- Four concrete next actions — this is the "where do we go from here?" conversation
- "Deploy to customer account" = swap synthetic data for theirs
- "Connect real data sources" = Snowpipe Streaming from POS/ecomm
- "Tune the model" = retrain with their labeled incidents
- "Scale the agent" = add notifications, case management integration

**Internal Context:**
- POC effort: ~2-3 weeks to connect real data and retrain the model
- Biggest risk: data quality of their labeled fraud cases. If labels are noisy, model performance will degrade.
- Pricing: all compute-based (warehouse + serverless for DTs + tokens for agent). No separate ML SKU.
