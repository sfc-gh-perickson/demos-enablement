"""Model Performance — latency, throughput, and error rates per model."""

import pandas as pd
import streamlit as st

df = st.session_state.get("df", pd.DataFrame())

if df.empty:
    st.warning("No trace data available for the current filters.")
    st.stop()

ok_df = df[df["STATUS_CODE"] == "STATUS_CODE_OK"].copy()

st.subheader("Model Comparison")

if ok_df.empty:
    st.warning("No successful spans in this window, so latency cannot be compared.")
    st.stop()

model_stats = (
    ok_df.groupby("REQUEST_MODEL")
    .agg(
        ok_spans=("TRACE_ID", "count"),
        avg_latency_ms=("DURATION_MS", "mean"),
        p50_latency_ms=("DURATION_MS", "median"),
        p95_latency_ms=("DURATION_MS", lambda s: s.quantile(0.95)),
        avg_output_tokens=("OUTPUT_TOKENS", "mean"),
    )
    .reset_index()
)

# Error rate is computed over all spans, not just successful ones.
totals = (
    df.assign(is_error=(df["STATUS_CODE"] == "STATUS_CODE_ERROR").astype(int))
    .groupby("REQUEST_MODEL")
    .agg(total=("TRACE_ID", "count"), errors=("is_error", "sum"))
    .reset_index()
)
model_stats = model_stats.merge(totals, on="REQUEST_MODEL", how="left")
model_stats["error_rate_pct"] = round(
    100.0 * model_stats["errors"] / model_stats["total"].replace(0, 1), 1
)

# Output throughput. Guard against zero-duration spans.
valid = ok_df[ok_df["DURATION_MS"] > 0].copy()
if not valid.empty:
    valid["tokens_per_sec"] = valid["OUTPUT_TOKENS"].fillna(0) / (
        valid["DURATION_MS"] / 1000.0
    )
    tps = (
        valid.groupby("REQUEST_MODEL")["tokens_per_sec"]
        .mean()
        .reset_index()
        .rename(columns={"tokens_per_sec": "avg_tokens_per_sec"})
    )
    model_stats = model_stats.merge(tps, on="REQUEST_MODEL", how="left")
else:
    model_stats["avg_tokens_per_sec"] = 0

display = model_stats.rename(
    columns={
        "REQUEST_MODEL": "Model",
        "ok_spans": "OK Spans",
        "avg_latency_ms": "Avg Latency (ms)",
        "p50_latency_ms": "p50 (ms)",
        "p95_latency_ms": "p95 (ms)",
        "avg_output_tokens": "Avg Output Tokens",
        "avg_tokens_per_sec": "Tokens/sec",
        "error_rate_pct": "Error Rate %",
    }
)[
    [
        "Model",
        "OK Spans",
        "Avg Latency (ms)",
        "p50 (ms)",
        "p95 (ms)",
        "Avg Output Tokens",
        "Tokens/sec",
        "Error Rate %",
    ]
]
for col in ["Avg Latency (ms)", "p50 (ms)", "p95 (ms)", "Avg Output Tokens", "Tokens/sec"]:
    display[col] = display[col].fillna(0).round(0).astype(int)

st.dataframe(display, hide_index=True, width="stretch")

if len(display) == 1:
    st.caption(
        f"Only one model (`{display['Model'].iloc[0]}`) appears in this window — "
        "the comparison charts below get interesting once traffic spans several models."
    )

st.divider()
col1, col2 = st.columns(2)
with col1:
    with st.container(border=True):
        st.caption("Latency by model (p50 vs p95)")
        # stack=False: stacked bars would sum p50 and p95 into a meaningless total.
        st.bar_chart(
            display[["Model", "p50 (ms)", "p95 (ms)"]].set_index("Model"),
            stack=False,
        )
with col2:
    with st.container(border=True):
        st.caption("Output throughput (tokens/sec)")
        st.bar_chart(display[["Model", "Tokens/sec"]].set_index("Model"), color="#29B5E8")

# --- Caller x Model ----------------------------------------------------------
st.divider()
st.subheader("Caller × Model")

matrix = (
    ok_df.groupby(["USER_NAME", "REQUEST_MODEL"])
    .agg(
        spans=("TRACE_ID", "count"),
        avg_latency=("DURATION_MS", lambda s: round(s.mean(), 0)),
        avg_tokens=("OUTPUT_TOKENS", lambda s: round(s.mean(), 0)),
    )
    .reset_index()
)
matrix.columns = ["Caller", "Model", "Spans", "Avg Latency (ms)", "Avg Output Tokens"]

pivot = matrix.pivot_table(
    index="Caller", columns="Model", values="Spans", fill_value=0, aggfunc="sum"
)
st.caption("Span count by caller and model — shows which workload routes where")
st.dataframe(pivot, width="stretch")

with st.expander("Full caller × model detail"):
    st.dataframe(
        matrix.sort_values(["Caller", "Avg Latency (ms)"]),
        hide_index=True,
        width="stretch",
    )
