"""Caller Deep Dive — one caller at a time, down to individual spans.

Against the lab in ../setup.sql this is a single-caller view, since all traffic
comes from one user. It earns its keep against real traffic, where each
application or service account appears separately.
"""

import pandas as pd
import streamlit as st

df = st.session_state.get("df", pd.DataFrame())

if df.empty:
    st.warning("No trace data available for the current filters.")
    st.stop()

callers = sorted(df["USER_NAME"].dropna().unique().tolist())
if not callers:
    st.warning("No caller identity on these spans.")
    st.stop()

selected = st.selectbox("Select caller", options=callers)

caller_df = df[df["USER_NAME"] == selected].copy()
ok_caller = caller_df[caller_df["STATUS_CODE"] == "STATUS_CODE_OK"]
err_caller = caller_df[caller_df["STATUS_CODE"] == "STATUS_CODE_ERROR"]

total = len(caller_df)
error_rate = round(100.0 * len(err_caller) / total, 1) if total else 0
avg_lat = round(ok_caller["DURATION_MS"].mean(), 0) if not ok_caller.empty else 0
p95_lat = round(ok_caller["DURATION_MS"].quantile(0.95), 0) if not ok_caller.empty else 0

with st.container(horizontal=True):
    st.metric("Spans", f"{total:,}", border=True)
    st.metric("Traces", f"{caller_df['TRACE_ID'].nunique():,}", border=True)
    st.metric("Error Rate", f"{error_rate}%", border=True)
    st.metric("Avg Latency", f"{avg_lat:,.0f} ms", border=True)
    st.metric("p95 Latency", f"{p95_lat:,.0f} ms", border=True)
    st.metric(
        "Input Tokens",
        f"{int(ok_caller['INPUT_TOKENS'].fillna(0).sum()):,}",
        border=True,
    )
    st.metric(
        "Output Tokens",
        f"{int(ok_caller['OUTPUT_TOKENS'].fillna(0).sum()):,}",
        border=True,
    )

st.divider()

col1, col2 = st.columns(2)

with col1:
    st.subheader("Models Used")
    if ok_caller.empty:
        st.info("No successful spans for this caller.")
    else:
        model_agg = (
            ok_caller.groupby("REQUEST_MODEL")
            .agg(
                spans=("TRACE_ID", "count"),
                avg_latency=("DURATION_MS", "mean"),
                p50_latency=("DURATION_MS", "median"),
                avg_output=("OUTPUT_TOKENS", "mean"),
            )
            .reset_index()
            .rename(
                columns={
                    "REQUEST_MODEL": "Model",
                    "spans": "Spans",
                    "avg_latency": "Avg Latency (ms)",
                    "p50_latency": "p50 (ms)",
                    "avg_output": "Avg Output Tokens",
                }
            )
        )
        for c in ["Avg Latency (ms)", "p50 (ms)", "Avg Output Tokens"]:
            model_agg[c] = model_agg[c].fillna(0).round(0).astype(int)
        st.dataframe(model_agg, hide_index=True, width="stretch")

with col2:
    st.subheader("Latency Over Time")
    # Per-span scatter rather than a bar chart: bars would sum durations per
    # model, which is not a latency reading.
    if ok_caller.empty:
        st.info("No successful spans to plot.")
    else:
        scatter = ok_caller[["START_TIMESTAMP", "DURATION_MS", "REQUEST_MODEL"]].copy()
        scatter["START_TIMESTAMP"] = pd.to_datetime(scatter["START_TIMESTAMP"], utc=True)
        st.scatter_chart(
            scatter,
            x="START_TIMESTAMP",
            y="DURATION_MS",
            color="REQUEST_MODEL",
        )

# --- Span detail -------------------------------------------------------------
st.divider()
st.subheader("Span Detail")

display_cols = [
    "TRACE_ID",
    "SPAN_NAME",
    "REQUEST_MODEL",
    "STATUS_CODE",
    "HTTP_STATUS",
    "DURATION_MS",
    "INPUT_TOKENS",
    "OUTPUT_TOKENS",
    "START_TIMESTAMP",
]
available = [c for c in display_cols if c in caller_df.columns]
st.caption("Spans sharing a TRACE_ID belong to the same end-to-end request.")
st.dataframe(
    caller_df[available].sort_values("START_TIMESTAMP", ascending=False),
    hide_index=True,
    width="stretch",
    height=400,
)
