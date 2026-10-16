"""SQL queries for the AI Gateway monitoring app.
Each function takes a Snowpark session and returns a pandas DataFrame."""

import streamlit as st
import pandas as pd

GATEWAY_NAME = "SNOWFLAKE"


def get_session():
    """Return a Snowpark session — works both in SiS and locally."""
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        return st.connection("parker_demo", type="snowflake").session()


def _complete(session, model, prompt):
    """Run a completion — SDK locally, SQL in SiS."""
    try:
        from cortex_agent_sdk import CortexAgentClient, AgentResponse
    except ImportError:
        return _complete_sql(session, model, prompt)

    try:
        import toml, os

        # Get account identifier
        account = session.sql(
            "SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME()"
        ).collect()[0][0]

        # Get PAT: SiS session token first, then config file
        try:
            with open('/snowflake/session/token', 'r') as f:
                pat = f.read().strip()
        except FileNotFoundError:
            cfg = toml.load(os.path.expanduser("~/.snowflake/config.toml"))
            pat = cfg["connections"]["parker_demo"]["password"]

        client = CortexAgentClient(account=account, auth=pat)
        conversation = client.conversations.create(
            origin_application="gateway_monitor",
            agent={"type": "coding", "spec": {"models": {"orchestration": "auto"}}},
        )
        turn = conversation.send(prompt)
        answer: AgentResponse = turn.result()
        return answer.text
    except Exception as e:
        st.warning(f"SDK call failed, falling back to SQL: {e}")
        return _complete_sql(session, model, prompt)


def _complete_sql(session, model, prompt):
    """Fallback: run completion via SNOWFLAKE.CORTEX.COMPLETE() SQL."""
    safe_prompt = prompt.replace("'", "''")
    result = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.COMPLETE(
            '{model}',
            $${safe_prompt}$$
        ) AS RESPONSE
    """).to_pandas()
    return result.iloc[0]["RESPONSE"] if not result.empty else ""


def _run(session, sql, params=None):
    if params:
        for p in params:
            sql = sql.replace("%s", f"'{p}'", 1)
    return session.sql(sql).to_pandas()


# ---------------------------------------------------------------------------
# Tab 1 — Overview Dashboard
# ---------------------------------------------------------------------------

def kpi_summary(session, days=7):
    return _run(session, f"""
        SELECT
            COUNT(*)                                AS TOTAL_REQUESTS,
            COUNT(DISTINCT TRACE:trace_id::STRING)  AS UNIQUE_TRACES,
            COUNT(DISTINCT RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING) AS MODELS_USED
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
    """)


def estimated_credits(session, days=7):
    return _run(session, f"""
        SELECT COALESCE(SUM(CREDITS), 0) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY
        WHERE START_TIME > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
    """)


def requests_per_hour(session, days=7):
    return _run(session, f"""
        SELECT
            DATE_TRUNC('hour', TIMESTAMP)                              AS HOUR,
            RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING           AS MODEL,
            COUNT(*)                                                    AS REQUEST_COUNT
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        GROUP BY 1, 2
        ORDER BY 1
    """)


def overview_latency(session, days=7):
    return _run(session, f"""
        SELECT
            RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING AS MODEL,
            COUNT(*) AS CALLS,
            ROUND(AVG(RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS AVG_SEC,
            ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS P50_SEC,
            ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS P90_SEC,
            ROUND(MAX(RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS MAX_SEC
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND RECORD_ATTRIBUTES:"gen_ai.client.operation.duration" IS NOT NULL
        GROUP BY 1
        ORDER BY CALLS DESC
    """)


def overview_tool_usage(session, days=7):
    return _run(session, f"""
        WITH spans AS (
            SELECT
                t.RECORD_ATTRIBUTES:"gen_ai.output.messages"::STRING AS OUT_MSGS,
                at.AGENT_NAME
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
            INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
                ON t.TRACE:trace_id::STRING = at.TRACE_ID
            WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
              AND OUT_MSGS IS NOT NULL
        ),
        tool_calls AS (
            SELECT
                s.AGENT_NAME,
                p.value:"name"::STRING AS TOOL_NAME
            FROM spans s,
                LATERAL FLATTEN(input => PARSE_JSON(s.OUT_MSGS)) m,
                LATERAL FLATTEN(input => m.value:"parts") p
            WHERE p.value:"type"::STRING = 'tool_call'
        )
        SELECT AGENT_NAME, TOOL_NAME, COUNT(*) AS CALL_COUNT
        FROM tool_calls
        GROUP BY 1, 2
        ORDER BY CALL_COUNT DESC
    """)


def requests_by_agent(session, days=7):
    return _run(session, f"""
        WITH traces AS (
            SELECT
                TRACE:trace_id::STRING                                      AS TRACE_ID,
                RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING            AS MODEL,
                RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT          AS INPUT_TOKENS,
                RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT         AS OUTPUT_TOKENS,
                RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT AS LATENCY_SEC
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
            WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        )
        SELECT
            COALESCE(at.AGENT_NAME, 'Unknown')  AS AGENT_NAME,
            t.MODEL,
            COUNT(*)                             AS REQUEST_COUNT,
            AVG(t.INPUT_TOKENS)                  AS AVG_INPUT_TOKENS,
            AVG(t.OUTPUT_TOKENS)                 AS AVG_OUTPUT_TOKENS,
            SUM(t.INPUT_TOKENS)                  AS TOTAL_INPUT_TOKENS,
            SUM(t.OUTPUT_TOKENS)                 AS TOTAL_OUTPUT_TOKENS,
            ROUND(AVG(t.LATENCY_SEC), 2)         AS AVG_LATENCY_SEC,
            ROUND(MAX(t.LATENCY_SEC), 2)         AS MAX_LATENCY_SEC
        FROM traces t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE_ID = at.TRACE_ID
        GROUP BY 1, 2
        ORDER BY REQUEST_COUNT DESC
    """)


# ---------------------------------------------------------------------------
# Tab 2 — Agent Explorer
# ---------------------------------------------------------------------------

def agent_list(session):
    return _run(session, """
        SELECT AGENT_NAME, DESCRIPTION
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENTS
        ORDER BY AGENT_NAME
    """)


def agent_model_usage(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            t.RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING   AS MODEL,
            COUNT(*)                                               AS REQUEST_COUNT,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT)  AS TOTAL_INPUT_TOKENS,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT) AS TOTAL_OUTPUT_TOKENS
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE:trace_id::STRING = at.TRACE_ID
        WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND at.AGENT_NAME = %s
        GROUP BY 1
        ORDER BY REQUEST_COUNT DESC
    """, (agent_name,))


def agent_token_trend(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            DATE_TRUNC('hour', t.TIMESTAMP)                              AS HOUR,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT)    AS INPUT_TOKENS,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT)   AS OUTPUT_TOKENS
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE:trace_id::STRING = at.TRACE_ID
        WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND at.AGENT_NAME = %s
        GROUP BY 1
        ORDER BY 1
    """, (agent_name,))


def agent_tool_usage(session, agent_name, days=7):
    return _run(session, f"""
        WITH agent_spans AS (
            SELECT
                t.RECORD_ATTRIBUTES:"gen_ai.input.messages"::STRING AS IN_MSGS,
                t.RECORD_ATTRIBUTES:"gen_ai.output.messages"::STRING AS OUT_MSGS
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
            INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
                ON t.TRACE:trace_id::STRING = at.TRACE_ID
            WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
              AND at.AGENT_NAME = %s
        ),
        tool_parts AS (
            SELECT p.value:"response" AS RESP
            FROM agent_spans,
                LATERAL FLATTEN(input => PARSE_JSON(IN_MSGS)) m,
                LATERAL FLATTEN(input => m.value:"parts") p
            WHERE IN_MSGS IS NOT NULL
              AND m.value:"role"::STRING = 'tool'
              AND RESP IS NOT NULL
        ),
        inner_content AS (
            SELECT TRY_PARSE_JSON(r.value:"text"::STRING) AS PARSED
            FROM tool_parts, LATERAL FLATTEN(input => RESP) r
            WHERE r.value:"text" IS NOT NULL
        ),
        inner_tools AS (
            SELECT c.value:"tool_use":"name"::STRING AS TOOL_NAME
            FROM inner_content, LATERAL FLATTEN(input => PARSED:"content") c
            WHERE PARSED IS NOT NULL
              AND c.value:"tool_use":"name" IS NOT NULL
        )
        SELECT TOOL_NAME, COUNT(*) AS CALL_COUNT
        FROM inner_tools
        GROUP BY 1
        ORDER BY 2 DESC
    """, (agent_name,))


def agent_credit_spend(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            t.RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING AS MODEL,
            COUNT(*)                                             AS REQUEST_COUNT,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT)  AS TOTAL_INPUT_TOKENS,
            SUM(t.RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT) AS TOTAL_OUTPUT_TOKENS
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE:trace_id::STRING = at.TRACE_ID
        WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND at.AGENT_NAME = %s
        GROUP BY 1
        ORDER BY TOTAL_INPUT_TOKENS DESC
    """, (agent_name,))


# ---------------------------------------------------------------------------
# Tab 3 — Topic Mining & Search
# ---------------------------------------------------------------------------

def all_user_messages(session, days=7):
    return _run(session, f"""
        WITH spans AS (
            SELECT
                TRACE:trace_id::STRING                                          AS TRACE_ID,
                TIMESTAMP,
                RECORD_ATTRIBUTES:"gen_ai.input.messages"::STRING               AS IN_MSGS
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
            WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
              AND IN_MSGS IS NOT NULL
        ),
        user_msgs AS (
            SELECT
                s.TRACE_ID,
                s.TIMESTAMP,
                p.value:"content"::STRING AS USER_MESSAGE
            FROM spans s,
                LATERAL FLATTEN(input => PARSE_JSON(s.IN_MSGS)) m,
                LATERAL FLATTEN(input => m.value:"parts") p
            WHERE m.value:"role"::STRING = 'user'
              AND p.value:"content" IS NOT NULL
        )
        SELECT
            u.TRACE_ID,
            u.TIMESTAMP,
            at.AGENT_NAME,
            u.USER_MESSAGE
        FROM user_msgs u
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON u.TRACE_ID = at.TRACE_ID
        ORDER BY u.TIMESTAMP DESC
    """)


def cached_topics(session):
    return _run(session, """
        SELECT TRACE_ID, USER_MESSAGE, TOPIC
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
    """)


def classify_topic(session, user_message):
    prompt = (
        "Classify the following user question into exactly one of these categories: "
        "analytics, strategy, comparison, executive_summary, cost_analysis, out_of_scope. "
        "Reply with only the category name, nothing else.\n\nQuestion: "
        + user_message
    )
    topic = _complete(session, "mistral-large2", prompt).strip()
    return pd.DataFrame([{"TOPIC": topic}])


def insert_topic_cache(session, trace_id, user_message, topic):
    safe_msg = user_message.replace("'", "''")
    session.sql(f"""
        INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
            (TRACE_ID, USER_MESSAGE, TOPIC)
        SELECT '{trace_id}', '{safe_msg}', '{topic}'
        WHERE NOT EXISTS (
            SELECT 1 FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
            WHERE TRACE_ID = '{trace_id}' AND USER_MESSAGE = '{safe_msg}'
        )
    """).collect()


def ensure_topic_cache_table(session):
    session.sql("""
        CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE (
            TRACE_ID    VARCHAR,
            USER_MESSAGE VARCHAR,
            TOPIC        VARCHAR,
            CLASSIFIED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
        )
    """).collect()


def ensure_recommendations_table(session):
    session.sql("""
        CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_RECOMMENDATIONS (
            TOPIC VARCHAR,
            RECOMMENDATIONS VARCHAR,
            GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
        )
    """).collect()


def cached_recommendations(session, topic):
    return _run(session, f"""
        SELECT RECOMMENDATIONS, GENERATED_AT
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_RECOMMENDATIONS
        WHERE TOPIC = %s
        ORDER BY GENERATED_AT DESC
        LIMIT 1
    """, (topic,))


def generate_topic_recommendations(session, topic, questions, feedback_lines):
    q_list = "\n".join(f"- {q}" for q in questions[:30])
    fb_list = "\n".join(f"- [{'+' if pos else '-'}] {msg}: {fb}" for pos, msg, fb in feedback_lines[:20])
    if not fb_list:
        fb_list = "(no feedback recorded)"

    prompt = f"""You are an AI platform advisor analyzing usage patterns for external agents routed through Snowflake's Cortex AI Gateway.

Topic category: {topic}

User questions in this category:
{q_list}

User feedback on responses:
{fb_list}

The agents currently have access to:
- Semantic View CMO_ANALYTICS on CAMPAIGN_SPEND (dimensions: channel, month, campaign_name; metrics: total_spend, total_revenue, roas, roi, cpc, cpa, total_impressions, total_clicks, total_conversions)
- Cortex Search Service STRATEGY_SEARCH_SVC on STRATEGY_DOCS (6 strategy/methodology documents)
- execute_sql tool for running generated SQL

Based on these questions and feedback, provide specific, actionable recommendations in these categories:

1. SEMANTIC VIEW GAPS — metrics, dimensions, or filters users need that CMO_ANALYTICS doesn't have
2. SEARCH SERVICE GAPS — document types or knowledge that STRATEGY_SEARCH_SVC should include
3. AGENT IMPROVEMENTS — system prompt changes, new tools, or better instructions
4. DATA GAPS — new tables or data sources needed

For each recommendation, be specific: name the metric/dimension/document/tool. Explain what user questions it would address."""

    recs = _complete(session, "mistral-large2", prompt)

    if recs:
        safe_recs = recs.replace("'", "''")
        session.sql(f"""
            INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_RECOMMENDATIONS
                (TOPIC, RECOMMENDATIONS)
            VALUES ('{topic}', $${safe_recs}$$)
        """).collect()
        return recs
    return "No recommendations generated."


# ---------------------------------------------------------------------------
# Agent Latency Analytics
# ---------------------------------------------------------------------------

def agent_latency_distribution(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT AS LATENCY_SEC,
            t.RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT AS INPUT_TOKENS,
            t.RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT AS OUTPUT_TOKENS,
            t.RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING AS MODEL,
            t.TIMESTAMP
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE:trace_id::STRING = at.TRACE_ID
        WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND at.AGENT_NAME = %s
          AND t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration" IS NOT NULL
        ORDER BY t.TIMESTAMP
    """, (agent_name,))


def agent_latency_percentiles(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            COUNT(*) AS TOTAL_CALLS,
            ROUND(AVG(t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS AVG_SEC,
            ROUND(MEDIAN(t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS P50_SEC,
            ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS P90_SEC,
            ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS P99_SEC,
            ROUND(MAX(t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT), 2) AS MAX_SEC
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
        INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE:trace_id::STRING = at.TRACE_ID
        WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND at.AGENT_NAME = %s
          AND t.RECORD_ATTRIBUTES:"gen_ai.client.operation.duration" IS NOT NULL
    """, (agent_name,))


# ---------------------------------------------------------------------------
# Skill / Workflow Suggestions
# ---------------------------------------------------------------------------

def generate_agent_suggestions(session, agent_name, questions, feedback_lines, latency_stats):
    q_list = "\n".join(f"- {q}" for q in questions[:30])
    fb_list = "\n".join(f"- [{'+' if pos else '-'}] {msg}: {fb}" for pos, msg, fb in feedback_lines[:20])
    if not fb_list:
        fb_list = "(no feedback)"

    lat_info = "No latency data"
    if latency_stats is not None and not latency_stats.empty:
        row = latency_stats.iloc[0]
        lat_info = f"Avg: {row['AVG_SEC']}s, P50: {row['P50_SEC']}s, P90: {row['P90_SEC']}s, P99: {row['P99_SEC']}s, Max: {row['MAX_SEC']}s"

    prompt = f"""You are an AI platform advisor. Analyze the usage patterns for the agent "{agent_name}" routed through Snowflake's Cortex AI Gateway and suggest improvements.

User questions this agent received:
{q_list}

User feedback:
{fb_list}

Latency profile: {lat_info}

Provide specific, actionable suggestions in these categories:

1. SKILL SUGGESTIONS — new tools or capabilities this agent should have (e.g., a forecasting tool, a benchmarking service, access to external data). Name each skill and what questions it would help answer.

2. WORKFLOW IMPROVEMENTS — multi-step workflows or chains this agent should implement (e.g., auto-validate SQL before executing, cross-reference strategy docs when answering data questions). Explain the workflow steps.

3. LATENCY OPTIMIZATIONS — based on the latency profile, suggest model changes (smaller model for simple queries, caching strategies), prompt optimizations (shorter system prompts, fewer tool round-trips), or architectural changes.

4. GUARDRAILS — patterns in the questions or feedback that suggest the agent needs better error handling, input validation, or scope boundaries.

Be specific and actionable. Reference the actual questions and feedback."""

    return _complete(session, "mistral-large2", prompt) or "No suggestions generated."


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

def feedback_summary(session, days=7):
    return _run(session, f"""
        SELECT
            AGENT_NAME,
            SUM(CASE WHEN IS_POSITIVE THEN 1 ELSE 0 END) AS POSITIVE,
            SUM(CASE WHEN NOT IS_POSITIVE THEN 1 ELSE 0 END) AS NEGATIVE,
            COUNT(*) AS TOTAL
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK
        WHERE CREATED_AT > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        GROUP BY 1
        ORDER BY TOTAL DESC
    """)


def feedback_detail(session, agent_name, days=7):
    return _run(session, f"""
        SELECT
            TRACE_ID, USER_MESSAGE, IS_POSITIVE, FEEDBACK_MESSAGE, CREATED_AT
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK
        WHERE CREATED_AT > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND AGENT_NAME = %s
        ORDER BY CREATED_AT DESC
    """, (agent_name,))


def top_users(session, days=7):
    return _run(session, f"""
        SELECT
            u.NAME AS USER_NAME,
            COUNT(*) AS REQUEST_COUNT,
            SUM(f.value:"input_tokens"::INT) AS TOTAL_INPUT_TOKENS,
            SUM(f.value:"output_tokens"::INT) AS TOTAL_OUTPUT_TOKENS,
            SUM(g.CREDITS) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY g
            JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON g.USER_ID = u.USER_ID
            ,LATERAL FLATTEN(input => g.OPERATION_DETAILS) f
        WHERE g.START_TIME > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        GROUP BY u.NAME
        ORDER BY TOTAL_CREDITS DESC
        LIMIT 20
    """)


# ---------------------------------------------------------------------------
# Tab 4 — Conversation Inspector
# ---------------------------------------------------------------------------

def agent_traces(session, agent_name, days=7):
    return _run(session, f"""
        WITH spans AS (
            SELECT
                t.TRACE:trace_id::STRING                                      AS TRACE_ID,
                MIN(t.TIMESTAMP)                                              AS FIRST_TS,
                COUNT(*)                                                      AS SPAN_COUNT
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
            INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
                ON t.TRACE:trace_id::STRING = at.TRACE_ID
            WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
              AND at.AGENT_NAME = %s
            GROUP BY 1
        )
        SELECT TRACE_ID, FIRST_TS, SPAN_COUNT
        FROM spans
        ORDER BY FIRST_TS DESC
    """, (agent_name,))


def trace_detail(session, trace_id):
    return _run(session, f"""
        SELECT
            TRACE:span_id::STRING                                           AS SPAN_ID,
            RECORD:name::STRING                                             AS SPAN_NAME,
            TIMESTAMP,
            RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING               AS MODEL,
            RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::INT             AS INPUT_TOKENS,
            RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::INT            AS OUTPUT_TOKENS,
            RECORD_ATTRIBUTES:"gen_ai.input.messages"::STRING              AS INPUT_MESSAGES,
            RECORD_ATTRIBUTES:"gen_ai.output.messages"::STRING             AS OUTPUT_MESSAGES,
            RECORD:status:code::STRING                                     AS STATUS_CODE,
            RECORD_ATTRIBUTES:"gen_ai.client.operation.duration"::FLOAT    AS LATENCY_SEC,
            RECORD_ATTRIBUTES:"http.status_code"::INT                      AS HTTP_STATUS
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TRACE:trace_id::STRING = %s
        ORDER BY TIMESTAMP
    """, (trace_id,))
