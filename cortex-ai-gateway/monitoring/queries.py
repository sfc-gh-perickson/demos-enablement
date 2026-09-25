"""All SQL queries for the AI Gateway monitoring app. Each function takes a
Snowflake connection and returns a pandas DataFrame."""

import pandas as pd

GATEWAY_NAME = "SNOWFLAKE"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run(conn, sql, params=None):
    cur = conn.cursor()
    try:
        cur.execute(sql, params or ())
        cols = [c[0] for c in cur.description] if cur.description else []
        rows = cur.fetchall()
        return pd.DataFrame(rows, columns=cols)
    finally:
        cur.close()

# ---------------------------------------------------------------------------
# Tab 1 — Overview Dashboard
# ---------------------------------------------------------------------------

def kpi_summary(conn, days=7):
    """Total requests, unique traces, distinct models, estimated credits."""
    return _run(conn, f"""
        SELECT
            COUNT(*)                                AS TOTAL_REQUESTS,
            COUNT(DISTINCT TRACE:trace_id::STRING)  AS UNIQUE_TRACES,
            COUNT(DISTINCT RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING) AS MODELS_USED
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
    """)


def estimated_credits(conn, days=7):
    """Total credits from usage history."""
    return _run(conn, f"""
        SELECT COALESCE(SUM(CREDITS), 0) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY
        WHERE START_TIME > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
    """)


def requests_per_hour(conn, days=7):
    """Time-series: requests per hour, broken out by model."""
    return _run(conn, f"""
        SELECT
            DATE_TRUNC('hour', TIMESTAMP)                              AS HOUR,
            RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING           AS MODEL,
            COUNT(*)                                                    AS REQUEST_COUNT
        FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}'))
        WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        GROUP BY 1, 2
        ORDER BY 1
    """)


def requests_by_agent(conn, days=7):
    """Requests per agent (via trace_id → agent name lookup)."""
    return _run(conn, f"""
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
        LEFT JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON t.TRACE_ID = at.TRACE_ID
        GROUP BY 1, 2
        ORDER BY REQUEST_COUNT DESC
    """)

# ---------------------------------------------------------------------------
# Tab 2 — Agent Explorer
# ---------------------------------------------------------------------------

def agent_list(conn):
    """Distinct agent names from the mapping table."""
    return _run(conn, """
        SELECT AGENT_NAME, DESCRIPTION
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENTS
        ORDER BY AGENT_NAME
    """)


def agent_model_usage(conn, agent_name, days=7):
    """Model breakdown for a single agent."""
    return _run(conn, f"""
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


def agent_token_trend(conn, agent_name, days=7):
    """Hourly token usage for a single agent."""
    return _run(conn, f"""
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


def agent_tool_usage(conn, agent_name, days=7):
    """Tool call counts extracted from output messages for a single agent."""
    return _run(conn, f"""
        WITH spans AS (
            SELECT t.RECORD_ATTRIBUTES:"gen_ai.output.messages"::STRING AS OUT_MSGS
            FROM TABLE(AGENT_TRACE_TABLE('{GATEWAY_NAME}')) t
            INNER JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
                ON t.TRACE:trace_id::STRING = at.TRACE_ID
            WHERE t.TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
              AND at.AGENT_NAME = %s
              AND OUT_MSGS IS NOT NULL
        ),
        tool_calls AS (
            SELECT
                p.value:"name"::STRING AS TOOL_NAME
            FROM spans,
                LATERAL FLATTEN(input => PARSE_JSON(OUT_MSGS)) m,
                LATERAL FLATTEN(input => m.value:"parts") p
            WHERE p.value:"type"::STRING = 'tool_call'
        )
        SELECT TOOL_NAME, COUNT(*) AS CALL_COUNT
        FROM tool_calls
        GROUP BY 1
        ORDER BY 2 DESC
    """, (agent_name,))


def agent_credit_spend(conn, days=7):
    """Credit spend from usage history, broken out by model."""
    return _run(conn, f"""
        SELECT
            f.key                                   AS MODEL,
            COUNT(*)                                 AS REQUEST_COUNT,
            SUM(f.value:"input_tokens"::INT)         AS TOTAL_INPUT_TOKENS,
            SUM(f.value:"output_tokens"::INT)        AS TOTAL_OUTPUT_TOKENS,
            SUM(CREDITS)                             AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY,
            LATERAL FLATTEN(input => OPERATION_DETAILS) f
        WHERE START_TIME > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
        GROUP BY f.key
        ORDER BY TOTAL_CREDITS DESC
    """)

# ---------------------------------------------------------------------------
# Tab 3 — Topic Mining & Search
# ---------------------------------------------------------------------------

def all_user_messages(conn, days=7):
    """Extract every user message from trace input messages, with agent + trace id."""
    return _run(conn, f"""
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
            COALESCE(at.AGENT_NAME, 'Unknown') AS AGENT_NAME,
            u.USER_MESSAGE
        FROM user_msgs u
        LEFT JOIN CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES at
            ON u.TRACE_ID = at.TRACE_ID
        ORDER BY u.TIMESTAMP DESC
    """)


def cached_topics(conn):
    """Read already-classified topics from the cache table."""
    return _run(conn, """
        SELECT TRACE_ID, USER_MESSAGE, TOPIC
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
    """)


def classify_topic(conn, user_message):
    """Classify a single user message into a topic using Cortex COMPLETE."""
    prompt = (
        "Classify the following user question into exactly one of these categories: "
        "analytics, strategy, comparison, executive_summary, cost_analysis, out_of_scope. "
        "Reply with only the category name, nothing else.\n\nQuestion: "
        + user_message.replace("'", "''")
    )
    return _run(conn, f"""
        SELECT TRIM(SNOWFLAKE.CORTEX.COMPLETE(
            'mistral-large2',
            $${prompt}$$
        )) AS TOPIC
    """)


def insert_topic_cache(conn, trace_id, user_message, topic):
    """Insert a classified topic into the cache."""
    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
                (TRACE_ID, USER_MESSAGE, TOPIC)
            SELECT %s, %s, %s
            WHERE NOT EXISTS (
                SELECT 1 FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE
                WHERE TRACE_ID = %s AND USER_MESSAGE = %s
            )
        """, (trace_id, user_message, topic, trace_id, user_message))
    finally:
        cur.close()


def ensure_topic_cache_table(conn):
    """Create the topic cache table if it doesn't exist."""
    cur = conn.cursor()
    try:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_TOPIC_CACHE (
                TRACE_ID    VARCHAR,
                USER_MESSAGE VARCHAR,
                TOPIC        VARCHAR,
                CLASSIFIED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
        """)
    finally:
        cur.close()

# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

def feedback_summary(conn, days=7):
    return _run(conn, f"""
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


def feedback_detail(conn, agent_name, days=7):
    return _run(conn, f"""
        SELECT
            TRACE_ID, USER_MESSAGE, IS_POSITIVE, FEEDBACK_MESSAGE, CREATED_AT
        FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK
        WHERE CREATED_AT > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
          AND AGENT_NAME = %s
        ORDER BY CREATED_AT DESC
    """, (agent_name,))


def top_users(conn, days=7):
    return _run(conn, f"""
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

def agent_traces(conn, agent_name, days=7):
    """List traces for a given agent, with span count."""
    return _run(conn, f"""
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
        SELECT
            TRACE_ID,
            FIRST_TS,
            SPAN_COUNT
        FROM spans
        ORDER BY FIRST_TS DESC
    """, (agent_name,))


def trace_detail(conn, trace_id):
    """Full conversation chain for a single trace — all spans in order."""
    return _run(conn, f"""
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
