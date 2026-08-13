# Cortex Agent Embedded App Context

Demonstrates how to scope Cortex Agent responses to the user's current context (page view, role, visible data) by injecting context into the **messages array** when calling a named Cortex Agent object.

## The Pattern

Same agent object + same semantic view + **different message context per page** = contextually relevant responses.

```
Application UI State  →  Messages Array  →  Named Cortex Agent  →  Scoped Response
(what user sees)         (context + question)  (tools pre-configured)  (tailored answer)
```

## Setup

### 1. Create demo objects

Run `setup.sql` in your Snowflake account. This creates:
- `CORTEX_AGENT_DEMO.ANALYTICS` schema
- Three tables with mock SaaS analytics data
- A semantic view (`ANALYTICS_ASSISTANT`) covering all tables
- A Cortex Agent object (`ANALYTICS_AGENT`) with Analyst tool pre-configured
- A Streamlit object (files deployed separately via CLI)

```sql
-- In Snowsight or SnowSQL:
!source setup.sql
```

### 2. Run locally

```bash
streamlit run app.py
```

Auth is handled automatically via PAT from `~/.snowflake/config.toml`.

### 3. Deploy to Streamlit-in-Snowflake

```bash
snow streamlit deploy --replace --prune --connection <your_connection>
```

The app is then available at:
```
https://app.snowflake.com/<ORG>/<ACCOUNT>/#/streamlit-apps/CORTEX_AGENT_DEMO.ANALYTICS.CONTEXT_SCOPED_AGENT_DEMO
```

### 4. (Optional) Explore the notebook

```bash
jupyter notebook demo_notebook.ipynb
```

The notebook uses PAT auth from `~/.snowflake/config.toml` to call the same named agent.

## Project Structure

```
├── setup.sql           # Creates tables, semantic view, agent, and streamlit object
├── snowflake.yml       # SiS deployment manifest
├── agent_client.py     # REST API client (SiS + local PAT support)
├── app.py              # Streamlit app with 3 scoped pages
├── demo_notebook.ipynb # Step-by-step walkthrough notebook
└── README.md           # This file
```

## How Context Injection Works

The Cortex Agent object (`ANALYTICS_AGENT`) is pre-configured with:
- Model (`claude-sonnet-4-5`)
- Tools (Cortex Analyst with the semantic view)
- Base instructions (persona, tone)

At runtime, the application injects **page context into the messages array**:

```python
payload = {
    "messages": [
        # Message 1: system message with current page context
        {"role": "system", "content": [{"type": "text", "text": f"Here is my current application context:\n{context}"}]},
        # Message 2: the actual user question
        {"role": "user", "content": [{"type": "text", "text": user_question}]},
    ],
    "stream": False,
}

# POST /api/v2/databases/CORTEX_AGENT_DEMO/schemas/ANALYTICS/agents/ANALYTICS_AGENT:run
```

No tools, tool_resources, models, or instructions in the request — all of that lives in the agent object.

## Pages in the Demo

| Page | Context Injected | Example Scoped Behavior |
|------|-----------------|------------------------|
| Executive Dashboard | KPIs, trends, alerts, VP role | Focuses on churn trend, strategic recommendations |
| Pipeline & Funnel | Stage data, segment, conversion rates, Sales role | Focuses on conversion drop-offs, deal velocity |
| Customer Segments | Segment attributes, retention, features, CSM role | Focuses on expansion opportunities, health signals |
