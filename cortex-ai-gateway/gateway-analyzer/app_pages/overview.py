"""Overview — traffic, errors, and how requests spread across models and callers."""

import pandas as pd
import streamlit as st

df = st.session_state.get("df", pd.DataFrame())

if df.empty:
    st.warning("No trace data available for the current filters.")
    st.stop()

ok_df = df[df["STATUS_CODE"] == "STATUS_CODE_OK"]
err_df = df[df["STATUS_CODE"] == "STATUS_CODE_ERROR"]

total_requests = len(df)
error_rate = round(100.0 * len(err_df) / total_requests, 1) if total_requests else 0
avg_latency = round(ok_df["DURATION_MS"].mean(), 0) if not ok_df.empty else 0
total_tokens = int(
    ok_df["INPUT_TOKENS"].fillna(0).sum() + ok_df["OUTPUT_TOKENS"].fillna(0).sum()
)

with st.container(horizontal=True):
    st.metric("Total Spans", f"{total_requests:,}", border=True)
    st.metric("Error Rate", f"{error_rate}%", border=True)
    st.metric("Avg Latency", f"{avg_latency:,.0f} ms", border=True)
    st.metric("Total Tokens", f"{total_tokens:,}", border=True)
    st.metric("Models", df["REQUEST_MODEL"].nunique(), border=True)
    st.metric("Callers", df["USER_NAME"].nunique(), border=True)

st.divider()

# --- Trace grouping ----------------------------------------------------------
# A trace with several spans means the client propagated a W3C traceparent
# header, so one agent turn was grouped. Single-span traces usually mean it did
# not. Surfacing this makes the difference visible.
spans_per_trace = df.groupby("TRACE_ID").size()
multi_span = int((spans_per_trace > 1).sum())
single_span = int((spans_per_trace == 1).sum())

col1, col2 = st.columns(2)
with col1:
    with st.container(border=True):
        st.caption("Trace grouping")
        st.markdown(
            f"**{multi_span}** multi-span trace{'s' if multi_span != 1 else ''} "
            f"· **{single_span}** single-span"
        )
        if multi_span == 0 and single_span > 1:
            st.info(
                "Every trace has one span. Clients are likely not sending a "
                "`traceparent` header, so multi-call agent turns cannot be "
                "grouped into a single trace."
            )
        else:
            st.caption(
                f"Max spans in one trace: {int(spans_per_trace.max())}. "
                "Multi-span traces indicate `traceparent` propagation is working."
            )
with col2:
    with st.container(border=True):
        st.caption("Spans per trace")
        dist = spans_per_trace.value_counts().sort_index().reset_index()
        dist.columns = ["Spans in trace", "Traces"]
        st.bar_chart(dist, x="Spans in trace", y="Traces", color="#29B5E8")

# --- Hourly traffic ----------------------------------------------------------
st.divider()
st.subheader("Traffic & Errors by Hour")

if "START_TIMESTAMP" in df.columns:
    ts_col = pd.to_datetime(df["START_TIMESTAMP"], utc=True)
    hourly = df.assign(
        hour=ts_col.dt.floor("h"),
        is_error=(df["STATUS_CODE"] == "STATUS_CODE_ERROR").astype(int),
    )
    hourly_agg = (
        hourly.groupby("hour")
        .agg(requests=("TRACE_ID", "count"), errors=("is_error", "sum"))
        .reset_index()
    )

    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.caption("Span volume by hour")
            st.bar_chart(hourly_agg, x="hour", y="requests", color="#29B5E8")
    with col2:
        with st.container(border=True):
            st.caption("Error count by hour")
            if hourly_agg["errors"].sum() > 0:
                st.bar_chart(hourly_agg, x="hour", y="errors", color="#E74C3C")
            else:
                st.success("No errors in the selected window.")

# --- Distribution by model and caller ----------------------------------------
st.divider()
col1, col2 = st.columns(2)

with col1:
    st.subheader("Spans by Model")
    model_counts = df["REQUEST_MODEL"].value_counts().reset_index()
    model_counts.columns = ["Model", "Spans"]
    st.bar_chart(model_counts, x="Model", y="Spans", color="#29B5E8")

with col2:
    st.subheader("Spans by Caller")
    caller_counts = df["USER_NAME"].value_counts().reset_index()
    caller_counts.columns = ["Caller", "Spans"]
    st.bar_chart(caller_counts, x="Caller", y="Spans", color="#11567F")
