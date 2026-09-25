"""Recommendations — rule-based findings derived from the observed spans.

Every rule fires off measured trace data, not guesswork. Thresholds are
deliberately conservative; tune them to the workload.
"""

import pandas as pd
import streamlit as st

df = st.session_state.get("df", pd.DataFrame())
gateway_name = st.session_state.get("gateway_name", "SNOWFLAKE")

if df.empty:
    st.warning("No trace data available for the current filters.")
    st.stop()

st.markdown(
    f"Findings derived from the spans currently in scope for gateway "
    f"`{gateway_name}` — latency, error rates, token usage, and model routing."
)

ok_df = df[df["STATUS_CODE"] == "STATUS_CODE_OK"].copy()

recommendations = []


def add_rec(severity, category, title, detail):
    recommendations.append(
        {"severity": severity, "category": category, "title": title, "detail": detail}
    )


# --- Rule 1: slow model behind an interactive caller -------------------------
INTERACTIVE_KEYWORDS = ["chat", "interactive", "assistant", "bot", "agent", "copilot"]
if not ok_df.empty:
    caller_model = (
        ok_df.groupby(["USER_NAME", "REQUEST_MODEL"])
        .agg(avg_lat=("DURATION_MS", "mean"), count=("TRACE_ID", "count"))
        .reset_index()
    )
    for _, row in caller_model.iterrows():
        caller_lower = str(row["USER_NAME"]).lower()
        if any(kw in caller_lower for kw in INTERACTIVE_KEYWORDS) and row["avg_lat"] > 10000:
            add_rec(
                "high",
                "Model Routing",
                f"High latency on an interactive caller: {row['USER_NAME']}",
                f"**{row['REQUEST_MODEL']}** averages **{row['avg_lat']:,.0f} ms** "
                f"across {int(row['count'])} spans. The caller name suggests an "
                f"interactive workload, where anything over ~5 s is felt by the user. "
                f"Consider routing this traffic to a faster model tier and reserving "
                f"the larger model for batch or high-stakes requests.",
            )

# --- Rule 2: elevated error rate per model ----------------------------------
model_err = (
    df.assign(is_error=(df["STATUS_CODE"] == "STATUS_CODE_ERROR").astype(int))
    .groupby("REQUEST_MODEL")
    .agg(total=("TRACE_ID", "count"), errors=("is_error", "sum"))
    .reset_index()
)
model_err["rate"] = 100.0 * model_err["errors"] / model_err["total"].replace(0, 1)
for _, row in model_err.iterrows():
    if row["rate"] > 5 and row["errors"] > 2:
        add_rec(
            "high",
            "Reliability",
            f"Elevated error rate on {row['REQUEST_MODEL']}: {row['rate']:.1f}%",
            f"**{int(row['errors'])}** of **{int(row['total'])}** spans failed. "
            f"A `503` means the gateway could not serve that model at that moment. "
            f"This is often transient capacity rather than a misconfiguration — the "
            f"same model may succeed hours earlier or later, so check whether this "
            f"model has successful spans in a wider lookback window before concluding "
            f"it is unavailable. Either way, retry with backoff and a documented "
            f"fallback model is the right client behaviour.",
        )

# --- Rule 3: large responses ------------------------------------------------
if not ok_df.empty:
    caller_tokens = (
        ok_df.groupby(["USER_NAME", "REQUEST_MODEL"])
        .agg(avg_out=("OUTPUT_TOKENS", "mean"), count=("TRACE_ID", "count"))
        .reset_index()
    )
    for _, row in caller_tokens.iterrows():
        if pd.notna(row["avg_out"]) and row["avg_out"] > 2000 and row["count"] >= 3:
            add_rec(
                "medium",
                "Prompt Engineering",
                f"Large responses: {row['USER_NAME']} on {row['REQUEST_MODEL']}",
                f"Averaging **{row['avg_out']:,.0f} output tokens** per span. Output "
                f"tokens drive both latency and credit consumption, so constrain them "
                f"in the system prompt (state the format and a length budget) and cap "
                f"them at the API. Note that OpenAI-family models on the gateway expect "
                f"`max_completion_tokens`, not `max_tokens`.",
            )

# --- Rule 4: slow models carrying most of the volume ------------------------
if not ok_df.empty:
    model_usage = ok_df["REQUEST_MODEL"].value_counts()
    model_latency = ok_df.groupby("REQUEST_MODEL")["DURATION_MS"].mean()
    fast_models = model_latency[model_latency < 3000].index.tolist()
    slow_models = model_latency[model_latency > 5000].index.tolist()
    if slow_models and fast_models:
        slow_total = sum(model_usage.get(m, 0) for m in slow_models)
        fast_total = sum(model_usage.get(m, 0) for m in fast_models)
        if slow_total > fast_total * 2:
            add_rec(
                "medium",
                "Cost Optimization",
                "Slower models carry most of the volume",
                f"Slower models ({', '.join(slow_models)}) handle **{slow_total}** spans "
                f"against **{fast_total}** for faster alternatives "
                f"({', '.join(fast_models)}). Worth testing whether the quality gap "
                f"justifies the latency and cost on the routine end of this workload.",
            )

# --- Rule 5: no conversation threading --------------------------------------
if "CONVERSATION_ID" in df.columns:
    has_conv = df["CONVERSATION_ID"].notna() & (df["CONVERSATION_ID"].astype(str) != "None")
    if not has_conv.any():
        add_rec(
            "low",
            "Observability",
            "No conversation IDs on any span",
            "Clients are not sending the `x-snowflake-ai-gateway-conversation-id` "
            "header. Adding it enables multi-turn conversation tracking in traces, "
            "which is what lets you measure session quality rather than single calls.",
        )

# --- Rule 6: traces that were never grouped ---------------------------------
spans_per_trace = df.groupby("TRACE_ID").size()
if len(spans_per_trace) > 2 and (spans_per_trace > 1).sum() == 0:
    add_rec(
        "medium",
        "Observability",
        "Every trace contains exactly one span",
        "No trace groups multiple gateway calls, which usually means clients are not "
        "propagating a W3C `traceparent` header. Without it, a single agent turn that "
        "makes several LLM calls is recorded as unrelated traces and the reasoning "
        "chain cannot be reconstructed. Send the same `traceparent` on every request "
        "within one turn.",
    )

# --- Rule 7: single-model callers -------------------------------------------
if not ok_df.empty:
    caller_models = ok_df.groupby("USER_NAME")["REQUEST_MODEL"].nunique()
    caller_volume = ok_df.groupby("USER_NAME").size()
    for caller in caller_models[caller_models == 1].index.tolist():
        if caller_volume.get(caller, 0) >= 5:
            model_used = ok_df[ok_df["USER_NAME"] == caller]["REQUEST_MODEL"].iloc[0]
            add_rec(
                "low",
                "Resilience",
                f"{caller} depends on a single model: {model_used}",
                f"All of this caller's traffic goes to **{model_used}**. If that model "
                f"becomes unavailable in the region, the requests fail rather than "
                f"falling back. Worth deciding now what the fallback should be.",
            )

# --- Display ----------------------------------------------------------------
st.divider()

if not recommendations:
    st.success(
        "No findings. Nothing in the current window crosses the thresholds for "
        "latency, error rate, response size, or routing."
    )
else:
    severity_icons = {"high": ":red[HIGH]", "medium": ":orange[MEDIUM]", "low": "LOW"}
    severity_order = {"high": 0, "medium": 1, "low": 2}
    recommendations.sort(key=lambda r: severity_order.get(r["severity"], 3))

    plural = "s" if len(recommendations) != 1 else ""
    st.subheader(f"{len(recommendations)} Finding{plural}")

    for rec in recommendations:
        with st.container(border=True):
            st.markdown(f"**{severity_icons.get(rec['severity'], '')}** | {rec['category']}")
            st.markdown(f"#### {rec['title']}")
            st.markdown(rec["detail"])

# --- General guidance -------------------------------------------------------
st.divider()
st.subheader("Working Effectively Through the Gateway")

st.markdown(
    """
**1. Send a `traceparent` header on every request in a turn**
> The gateway groups spans by trace ID. Without a shared
> [W3C `traceparent`](https://www.w3.org/TR/trace-context/), each call in a
> multi-step agent turn lands as its own trace and the chain cannot be rebuilt.

**2. Constrain output in the prompt, then cap it at the API**
> State the structure and a length budget ("three sections, under 100 words each")
> rather than relying on the cap alone. OpenAI-family models on the gateway expect
> `max_completion_tokens`; `max_tokens` is rejected.

**3. Match the model tier to the task**
> Small/fast models for classification, routing, and short summaries. Standard
> models for multi-section reports and tool-using agents. Large models for genuine
> multi-step reasoning. The Model Performance tab shows what each tier actually
> costs you in latency here.

**4. Verify model availability before building on it**
> Availability varies by region *and over time*, even with
> `CORTEX_ENABLED_CROSS_REGION` set. A `503` means the gateway could not serve the
> model at that moment; it is frequently transient capacity rather than a config
> error, so a model that fails today may have succeeded yesterday. Widen the
> lookback window on the Model Performance tab to see whether a model has ever
> succeeded here before ruling it out.

**5. Keep the gateway on the inference path**
> Only traffic through `/api/v2/aigateways/<gateway>/v1` is logged, metered, and
> subject to the model allowlist, budgets, and quotas. The standalone Cortex
> Inference REST API at `/api/v2/cortex/v1` also answers, so a misconfigured
> `base_url` silently produces no telemetry — if this app looks emptier than
> expected, check that first.

**6. Use the traffic view to find batch windows**
> The Overview tab's hourly chart shows where the quiet hours are, which is where
> non-interactive work belongs.
"""
)
