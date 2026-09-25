"""Gateway Analyzer — Cortex AI Gateway trace analysis.

Reads OpenTelemetry spans emitted by the account's Cortex AI Gateway and turns
them into traffic, latency, token, and routing views.

Data source: TABLE(AGENT_TRACE_TABLE(<gateway>)), which is populated only when
the gateway spec has logging enabled. Section 9 of ../setup.sql does that.
"""

import os

import streamlit as st

# The AI Gateway is auto-provisioned per account and named SNOWFLAKE. This must
# match the object that ../setup.sql configures:
#     ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$ ... $$;
# Confirm with SHOW AI GATEWAYS. Override via the GATEWAY_NAME env var if your
# account exposes the gateway under a different name.
GATEWAY_NAME = os.getenv("GATEWAY_NAME", "SNOWFLAKE")

st.set_page_config(
    page_title="Gateway Analyzer",
    page_icon=":material/monitoring:",
    layout="wide",
)

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))

# Columns converted from Snowflake Decimal to float for pandas math.
NUMERIC_COLS = ["DURATION_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "HTTP_STATUS"]


@st.cache_data(ttl="5m", show_spinner=False)
def load_trace_data(_conn, gateway_name, lookback_days):
    """Fetch gateway spans for the lookback window.

    One row per span. An agent turn that makes several LLM calls produces
    several spans sharing one TRACE_ID -- but only if the client sent a W3C
    traceparent header. Without it every call gets its own trace_id.
    """
    return _conn.query(
        """
        SELECT
            trace:"trace_id"::STRING                                       AS trace_id,
            trace:"span_id"::STRING                                        AS span_id,
            record:"name"::STRING                                          AS span_name,
            record_attributes:"gen_ai.operation.name"::STRING              AS operation,
            record_attributes:"gen_ai.request.model"::STRING               AS request_model,
            record_attributes:"gen_ai.response.model"::STRING              AS response_model,
            resource_attributes:"user"::STRING                             AS user_name,
            record:"status":"code"::STRING                                 AS status_code,
            TRY_TO_NUMBER(record_attributes:"http.status_code"::STRING)    AS http_status,
            start_timestamp,
            timestamp                                                      AS end_timestamp,
            DATEDIFF('millisecond', start_timestamp, timestamp)            AS duration_ms,
            TRY_TO_NUMBER(record_attributes:"gen_ai.usage.input_tokens"::STRING)  AS input_tokens,
            TRY_TO_NUMBER(record_attributes:"gen_ai.usage.output_tokens"::STRING) AS output_tokens,
            record_attributes:"gen_ai.conversation.id"::STRING             AS conversation_id,
            scope:"name"::STRING                                           AS scope_name
        FROM TABLE(AGENT_TRACE_TABLE(?))
        WHERE timestamp >= DATEADD('day', ?, CURRENT_TIMESTAMP())
        ORDER BY start_timestamp DESC
        """,
        params=[gateway_name, -lookback_days],
    )


# --- Sidebar: shared filters -------------------------------------------------
with st.sidebar:
    st.title(":material/monitoring: Gateway Analyzer")
    st.caption("Cortex AI Gateway trace analysis")
    st.divider()

    lookback = st.selectbox(
        "Lookback window",
        options=[1, 7, 14, 30],
        index=1,
        format_func=lambda d: f"{d} day{'s' if d > 1 else ''}",
    )

    with st.spinner("Loading traces..."):
        try:
            raw_df = load_trace_data(conn, GATEWAY_NAME, lookback)
        except Exception as exc:  # noqa: BLE001 - surface the cause to the user
            st.error(
                f"Could not read traces for gateway `{GATEWAY_NAME}`.\n\n"
                f"`{exc}`\n\n"
                "Check that `SHOW AI GATEWAYS` lists this name and that its spec "
                "has `logging.enabled: true` (section 9 of `setup.sql`)."
            )
            st.stop()

    if raw_df.empty:
        st.warning("No spans in this window.")
    else:
        for col in NUMERIC_COLS:
            if col in raw_df.columns:
                raw_df[col] = raw_df[col].astype("Float64").astype("float")

    df = raw_df.copy()

    # Free-text filter across the user and span-name columns. Left empty by
    # default so the app opens on everything the gateway has seen.
    search = st.text_input(
        "Filter",
        value="",
        placeholder="e.g. gpt-5, chat, a service account name",
        help=(
            "Space-separated keywords, matched against user and span name. "
            "Leave empty to show all traces."
        ),
    )
    if search.strip() and not df.empty:
        haystack = (
            df["USER_NAME"].fillna("").str.lower()
            + " "
            + df["SPAN_NAME"].fillna("").str.lower()
        )
        keywords = [kw.lower() for kw in search.split() if kw.strip()]
        mask = haystack.apply(lambda h: any(kw in h for kw in keywords))
        if mask.any():
            df = df[mask].copy()
        else:
            st.info("No spans matched the filter. Showing all traces.")

    # Caller filter. In a single-user lab this is a one-item list; against real
    # traffic it separates each application or service account.
    if not df.empty:
        all_users = sorted(df["USER_NAME"].dropna().unique().tolist())
        selected_users = st.multiselect(
            "Callers",
            options=all_users,
            default=all_users,
            help="Snowflake user or service account that made the request.",
        )
        if selected_users:
            df = df[df["USER_NAME"].isin(selected_users)]

        all_models = sorted(df["REQUEST_MODEL"].dropna().unique().tolist())
        selected_models = st.multiselect(
            "Models",
            options=all_models,
            default=all_models,
            help="Filter to specific models.",
        )
        if selected_models:
            df = df[df["REQUEST_MODEL"].isin(selected_models)]

    st.divider()
    if st.button(":material/refresh: Refresh data", width="stretch"):
        load_trace_data.clear()
        st.rerun()

    st.caption(f"{len(df):,} of {len(raw_df):,} spans shown")
    st.caption(f"Gateway: `{GATEWAY_NAME}`")

# Shared with the pages below.
st.session_state["df"] = df
st.session_state["raw_df"] = raw_df
st.session_state["conn"] = conn
st.session_state["gateway_name"] = GATEWAY_NAME

# --- Navigation --------------------------------------------------------------
page = st.navigation(
    [
        st.Page("app_pages/overview.py", title="Overview", icon=":material/dashboard:"),
        st.Page(
            "app_pages/model_performance.py",
            title="Model Performance",
            icon=":material/speed:",
        ),
        st.Page(
            "app_pages/service_deep_dive.py",
            title="Caller Deep Dive",
            icon=":material/account_tree:",
        ),
        st.Page(
            "app_pages/skills_advisor.py",
            title="Recommendations",
            icon=":material/lightbulb:",
        ),
    ],
    position="top",
)

page.run()
