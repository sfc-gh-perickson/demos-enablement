# Demo Script: Proactive Fraud Detection (15 minutes)

## Setup (before demo)

Run steps 1-4 from README.md. Ensure the investigation batch has been called at least once so reports exist.

---

## Act 1: The Data Pipeline (3 min)

**Narrative:** "Financial fraud costs institutions billions annually. Traditional rule-based systems catch known patterns but miss emerging threats. Let me show you a proactive approach using Snowflake's native ML and AI capabilities."

### Show:
1. Open Snowsight → FRAUD_DETECTION_DEMO database
2. Navigate to RAW.TRANSACTIONS — "500K synthetic transactions with 5 embedded fraud patterns"
3. Show CURATED.TRANSACTIONS_ENRICHED dynamic table
   - "Within 5 minutes of new transactions landing, this enriches with customer context and computes features like distance from home"
4. Show CURATED.CUSTOMER_FEATURE_BASE
   - "Per-customer behavioral aggregates: velocity, amounts, geo spread — all automatically refreshed"

**Key point:** "No orchestration code. No Airflow DAGs. Dynamic tables handle it natively."

---

## Act 2: ML with Explainability (4 min)

**Narrative:** "A model that says 'this is fraud' isn't enough. Investigators need to know WHY."

### Show:
1. Query the feature store:
   ```sql
   SELECT * FROM FEATURES."FRAUD_FEATURES$V1" WHERE CUSTOMER_ID = 'CUST-000052' LIMIT 1;
   ```
   - "18 behavioral features managed by Snowflake's Feature Store"

2. Show model in registry:
   ```sql
   SHOW MODELS IN SCHEMA MODELS;
   ```

3. Query SHAP explanations:
   ```sql
   SELECT CUSTOMER_ID, FRAUD_PROBABILITY, TOP_FACTORS
   FROM FEATURES.SHAP_SUMMARY
   WHERE FRAUD_PROBABILITY > 0.99
   LIMIT 5;
   ```
   - "SHAP tells us exactly which features drove each prediction — not just a score, but a story"

**Key point:** "Model registry + SHAP = auditable, explainable AI. Critical for regulatory compliance."

---

## Act 3: Agent Investigation (4 min)

**Narrative:** "Now the exciting part — an AI agent that proactively investigates the highest-risk customers."

### Show:
1. Priorities table:
   ```sql
   SELECT CUSTOMER_ID, FRAUD_PROBABILITY, PRIORITY_RANK, INVESTIGATION_STATUS
   FROM APP.PRIORITIES
   ORDER BY PRIORITY_RANK
   LIMIT 10;
   ```

2. Run a live investigation:
   ```sql
   CALL APP.RUN_INVESTIGATION_BATCH(3);
   ```

3. Show the investigation report:
   ```sql
   SELECT CUSTOMER_ID, RECOMMENDED_ACTION, INVESTIGATION_REPORT, THREAD_ID
   FROM APP.INVESTIGATION_REPORTS
   ORDER BY INVESTIGATED_AT DESC
   LIMIT 1;
   ```
   - "The agent analyzed the SHAP factors, identified the fraud pattern, and recommended an action"
   - "Critically — it saved the thread_id. An analyst can continue this conversation with full context."

**Key point:** "The agent doesn't replace the investigator — it prepares the case so they can act immediately."

---

## Act 4: The Investigation Portal (4 min)

**Narrative:** "Let's see what the analyst sees."

### Show:
1. Open the SAR app → Dashboard
   - Priority table with fraud probability bars, SHAP factor chips, status badges
   - "At a glance: 100 cases ranked by risk, with the key factors highlighted"

2. Click "Investigate" on a high-priority customer
   - **Left:** SHAP waterfall chart — "These 5 features drove the prediction"
   - **Center:** Agent report rendered as markdown — "The AI already investigated"
   - **Right:** Chat panel — "And I can continue the conversation"

3. Type a follow-up question in the chat:
   - "What specific transactions in the last 24 hours look most suspicious?"
   - The agent responds with context from the original investigation thread

4. Click "Escalate" → status updates to ESCALATED

**Key point:** "From data to decision in minutes, not days. The analyst confirms, doesn't discover."

---

## Closing (1 min)

**Summary:**
- Dynamic tables eliminate pipeline complexity
- Feature Store provides governed, consistent features
- SHAP makes ML explainable and auditable
- Cortex Agent does the heavy lifting of investigation
- Thread-based chat enables human-in-the-loop follow-up
- SAR app provides the operational interface

**Call to action:** "This entire pipeline runs natively in Snowflake — no external services, no data movement, no infrastructure to manage."
