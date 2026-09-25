"""AI Gateway Monitoring — Streamlit-in-Snowflake version."""

import json
import streamlit as st
import plotly.express as px
from snowflake.snowpark.context import get_active_session

import queries

# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

session = get_active_session()

# ---------------------------------------------------------------------------
# Page config
# ---------------------------------------------------------------------------

st.set_page_config(page_title="AI Gateway Monitor", layout="wide")
st.title("AI Gateway Monitor")

tab1, tab2, tab3, tab4 = st.tabs([
    "Overview Dashboard",
    "Agent Explorer",
    "Topic Mining & Search",
    "Conversation Inspector",
])

# ===== Tab 1: Overview Dashboard ==========================================
with tab1:
    days = st.slider("Lookback (days)", 1, 30, 7, key="overview_days")

    kpi = queries.kpi_summary(session, days)
    credits_df = queries.estimated_credits(session, days)

    if not kpi.empty:
        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Total Requests", f"{int(kpi.iloc[0]['TOTAL_REQUESTS']):,}")
        c2.metric("Unique Traces", f"{int(kpi.iloc[0]['UNIQUE_TRACES']):,}")
        c3.metric("Models Used", int(kpi.iloc[0]["MODELS_USED"]))
        c4.metric("Credits", f"{float(credits_df.iloc[0]['TOTAL_CREDITS']):.4f}")
        fb = queries.feedback_summary(session, days)
        if not fb.empty:
            pos = int(fb["POSITIVE"].sum())
            neg = int(fb["NEGATIVE"].sum())
            c5.metric("Feedback", f"+{pos} / -{neg}")

    rph = queries.requests_per_hour(session, days)
    if not rph.empty:
        fig = px.line(
            rph, x="HOUR", y="REQUEST_COUNT", color="MODEL",
            title="Requests per Hour by Model",
        )
        st.plotly_chart(fig, use_container_width=True)

    rba = queries.requests_by_agent(session, days)
    if not rba.empty:
        col_left, col_right = st.columns(2)
        with col_left:
            fig2 = px.bar(
                rba, x="AGENT_NAME", y="REQUEST_COUNT", color="MODEL",
                title="Requests by Agent",
            )
            st.plotly_chart(fig2, use_container_width=True)
        with col_right:
            st.subheader("Per-Agent Summary")
            display_cols = [
                "AGENT_NAME", "MODEL", "REQUEST_COUNT",
                "AVG_INPUT_TOKENS", "AVG_OUTPUT_TOKENS",
                "AVG_LATENCY_SEC", "MAX_LATENCY_SEC",
            ]
            st.dataframe(rba[[c for c in display_cols if c in rba.columns]])
    else:
        st.info("No agent data found. Run simulate.py first to populate gateway traces.")

    # Latency by model + tool usage breakdown
    lat_col, tool_col = st.columns(2)
    with lat_col:
        lat_overview = queries.overview_latency(session, days)
        if not lat_overview.empty:
            fig = px.bar(
                lat_overview, x="MODEL", y=["AVG_SEC", "P50_SEC", "P90_SEC", "MAX_SEC"],
                title="Latency by Model (seconds)", barmode="group",
            )
            fig.update_layout(yaxis_title="Seconds", legend_title="Percentile")
            st.plotly_chart(fig, use_container_width=True)
    with tool_col:
        tool_overview = queries.overview_tool_usage(session, days)
        if not tool_overview.empty:
            fig = px.bar(
                tool_overview, x="TOOL_NAME", y="CALL_COUNT", color="AGENT_NAME",
                title="Tool Usage Across Agents", barmode="group",
            )
            st.plotly_chart(fig, use_container_width=True)

# ===== Tab 2: Agent Explorer ===============================================
with tab2:
    agents_df = queries.agent_list(session)
    if agents_df.empty:
        st.info("No agents registered. Run simulate.py to create agent mappings.")
    else:
        agent_name = st.selectbox(
            "Select Agent",
            agents_df["AGENT_NAME"].tolist(),
            key="agent_select",
        )
        days2 = st.slider("Lookback (days)", 1, 30, 7, key="explorer_days")

        mu = queries.agent_model_usage(session, agent_name, days2)
        if not mu.empty:
            col1, col2 = st.columns(2)
            with col1:
                fig = px.pie(mu, names="MODEL", values="REQUEST_COUNT", title="Model Usage")
                st.plotly_chart(fig, use_container_width=True)
            with col2:
                st.dataframe(mu)

        tt = queries.agent_token_trend(session, agent_name, days2)
        if not tt.empty:
            fig = px.line(
                tt, x="HOUR", y=["INPUT_TOKENS", "OUTPUT_TOKENS"],
                title=f"Token Trend — {agent_name}",
            )
            st.plotly_chart(fig, use_container_width=True)

        tu = queries.agent_tool_usage(session, agent_name, days2)
        if not tu.empty:
            fig = px.bar(tu, x="TOOL_NAME", y="CALL_COUNT", color="TOOL_NAME", title="Tool Usage")
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.caption("No tool calls recorded for this agent.")

        cs = queries.agent_credit_spend(session, days2)
        if not cs.empty:
            st.subheader("Credit Spend (all agents)")
            st.dataframe(cs)

        # Top users
        tu_users = queries.top_users(session, days2)
        if not tu_users.empty:
            st.subheader("Top Users")
            st.dataframe(tu_users)

        # Feedback
        fb_detail = queries.feedback_detail(session, agent_name, days2)
        if not fb_detail.empty:
            st.subheader("Feedback")
            pos_count = int((fb_detail["IS_POSITIVE"] == True).sum())
            neg_count = int((fb_detail["IS_POSITIVE"] == False).sum())
            fc1, fc2 = st.columns(2)
            fc1.metric("Positive", pos_count)
            fc2.metric("Negative", neg_count)
            for _, row in fb_detail.iterrows():
                icon = "+" if row["IS_POSITIVE"] else "-"
                with st.expander(f"[{icon}] {row['USER_MESSAGE'][:100]}"):
                    st.markdown(f"**Feedback:** {row['FEEDBACK_MESSAGE']}")
                    st.markdown(f"**Trace:** `{row['TRACE_ID']}`")
                    st.markdown(f"**Time:** {row['CREATED_AT']}")
        else:
            st.caption("No feedback recorded for this agent.")

        # Latency analytics
        st.divider()
        st.subheader("Latency Analytics")

        lat_pct = queries.agent_latency_percentiles(session, agent_name, days2)
        if not lat_pct.empty and lat_pct.iloc[0]["TOTAL_CALLS"] > 0:
            row = lat_pct.iloc[0]
            lc1, lc2, lc3, lc4, lc5 = st.columns(5)
            lc1.metric("Avg", f"{row['AVG_SEC']}s")
            lc2.metric("P50", f"{row['P50_SEC']}s")
            lc3.metric("P90", f"{row['P90_SEC']}s")
            lc4.metric("P99", f"{row['P99_SEC']}s")
            lc5.metric("Max", f"{row['MAX_SEC']}s")

            lat_dist = queries.agent_latency_distribution(session, agent_name, days2)
            if not lat_dist.empty:
                col_hist, col_scatter = st.columns(2)
                with col_hist:
                    fig = px.histogram(lat_dist, x="LATENCY_SEC", nbins=20,
                                       title="Latency Distribution", color="MODEL")
                    st.plotly_chart(fig, use_container_width=True)
                with col_scatter:
                    fig = px.scatter(lat_dist, x="INPUT_TOKENS", y="LATENCY_SEC",
                                     color="MODEL", title="Latency vs Input Tokens",
                                     hover_data=["OUTPUT_TOKENS"])
                    st.plotly_chart(fig, use_container_width=True)
        else:
            st.caption("No latency data available.")

        # Skill & workflow suggestions
        st.divider()
        st.subheader("Skill & Workflow Suggestions")

        if st.button(f"Generate suggestions for {agent_name}", key="gen_suggestions"):
            with st.spinner("Analyzing conversations, feedback, and latency..."):
                agent_msgs = queries.all_user_messages(session, days2)
                if not agent_msgs.empty:
                    agent_msgs = agent_msgs[agent_msgs["AGENT_NAME"] == agent_name]
                    agent_questions = agent_msgs["USER_MESSAGE"].drop_duplicates().tolist()
                else:
                    agent_questions = []

                fb_lines = []
                fb_d = queries.feedback_detail(session, agent_name, days2)
                if not fb_d.empty:
                    for _, r in fb_d.iterrows():
                        fb_lines.append((r["IS_POSITIVE"], r["USER_MESSAGE"], r["FEEDBACK_MESSAGE"]))

                suggestions = queries.generate_agent_suggestions(
                    session, agent_name, agent_questions, fb_lines, lat_pct
                )
            st.markdown(suggestions)

# ===== Tab 3: Topic Mining & Search ========================================
with tab3:
    days3 = st.slider("Lookback (days)", 1, 30, 7, key="topic_days")

    queries.ensure_topic_cache_table(session)
    queries.ensure_recommendations_table(session)

    msgs = queries.all_user_messages(session, days3)
    if msgs.empty:
        st.info("No user messages found in traces.")
    else:
        msgs = msgs.drop_duplicates(subset=["TRACE_ID", "USER_MESSAGE"])

        cached = queries.cached_topics(session)
        cached_lookup = {}
        if not cached.empty:
            cached_lookup = dict(zip(
                zip(cached["TRACE_ID"], cached["USER_MESSAGE"]),
                cached["TOPIC"],
            ))

        uncached = msgs[
            ~msgs.apply(lambda r: (r["TRACE_ID"], r["USER_MESSAGE"]) in cached_lookup, axis=1)
        ]
        if not uncached.empty:
            if st.button(f"Classify {len(uncached)} uncategorized messages"):
                bar = st.progress(0)
                for i, (_, row) in enumerate(uncached.iterrows()):
                    result = queries.classify_topic(session, row["USER_MESSAGE"])
                    topic = result.iloc[0]["TOPIC"].strip().lower() if not result.empty else "out_of_scope"
                    queries.insert_topic_cache(session, row["TRACE_ID"], row["USER_MESSAGE"], topic)
                    cached_lookup[(row["TRACE_ID"], row["USER_MESSAGE"])] = topic
                    bar.progress((i + 1) / len(uncached))
                st.experimental_rerun()

        msgs["TOPIC"] = msgs.apply(
            lambda r: cached_lookup.get((r["TRACE_ID"], r["USER_MESSAGE"]), "unclassified"),
            axis=1,
        )

        topic_counts = msgs.groupby(["AGENT_NAME", "TOPIC"]).size().reset_index(name="COUNT")
        if not topic_counts.empty:
            fig = px.bar(
                topic_counts, x="TOPIC", y="COUNT", color="AGENT_NAME",
                title="Topic Distribution Across Agents", barmode="group",
            )
            st.plotly_chart(fig, use_container_width=True)

        # Thematic view — browse by topic across all agents
        topics_available = sorted(msgs["TOPIC"].unique())
        selected_topic = st.selectbox("Browse by Topic", ["All Topics"] + topics_available, key="topic_browse")

        search = st.text_input("Search user messages", key="topic_search")

        filtered = msgs
        if selected_topic != "All Topics":
            filtered = filtered[filtered["TOPIC"] == selected_topic]
        if search:
            filtered = filtered[filtered["USER_MESSAGE"].str.contains(search, case=False, na=False)]

        st.subheader(f"{selected_topic} ({len(filtered)} messages)")

        if selected_topic != "All Topics" and not filtered.empty:
            agent_breakdown = filtered.groupby("AGENT_NAME").size().reset_index(name="COUNT")
            cols = st.columns(len(agent_breakdown))
            for i, (_, row) in enumerate(agent_breakdown.iterrows()):
                cols[i].metric(row["AGENT_NAME"], row["COUNT"])

        for _, row in filtered.iterrows():
            with st.expander(f"[{row['AGENT_NAME']}] {row['USER_MESSAGE'][:120]}"):
                st.markdown(f"**Agent:** {row['AGENT_NAME']}")
                st.markdown(f"**Topic:** {row['TOPIC']}")
                st.markdown(f"**Trace:** `{row['TRACE_ID']}`")
                st.markdown(f"**Timestamp:** {row['TIMESTAMP']}")

        # Recommendations for the selected topic
        if selected_topic != "All Topics" and selected_topic != "unclassified":
            st.divider()
            st.subheader(f"Recommendations: {selected_topic}")

            cached_recs = queries.cached_recommendations(session, selected_topic)
            if not cached_recs.empty:
                st.markdown(cached_recs.iloc[0]["RECOMMENDATIONS"])
                st.caption(f"Generated: {cached_recs.iloc[0]['GENERATED_AT']}")
                if st.button("Regenerate", key="regen_recs"):
                    topic_questions = filtered["USER_MESSAGE"].tolist()
                    fb_df = queries.feedback_summary(session, days3)
                    fb_detail_all = []
                    for agent in filtered["AGENT_NAME"].unique():
                        fd = queries.feedback_detail(session, agent, days3)
                        if not fd.empty:
                            trace_ids = set(filtered["TRACE_ID"].tolist())
                            fd = fd[fd["TRACE_ID"].isin(trace_ids)]
                            for _, r in fd.iterrows():
                                fb_detail_all.append((r["IS_POSITIVE"], r["USER_MESSAGE"], r["FEEDBACK_MESSAGE"]))
                    recs = queries.generate_topic_recommendations(session, selected_topic, topic_questions, fb_detail_all)
                    st.experimental_rerun()
            else:
                if st.button(f"Generate Recommendations for '{selected_topic}'", key="gen_recs"):
                    with st.spinner("Analyzing questions and feedback..."):
                        topic_questions = filtered["USER_MESSAGE"].tolist()
                        fb_detail_all = []
                        for agent in filtered["AGENT_NAME"].unique():
                            fd = queries.feedback_detail(session, agent, days3)
                            if not fd.empty:
                                trace_ids = set(filtered["TRACE_ID"].tolist())
                                fd = fd[fd["TRACE_ID"].isin(trace_ids)]
                                for _, r in fd.iterrows():
                                    fb_detail_all.append((r["IS_POSITIVE"], r["USER_MESSAGE"], r["FEEDBACK_MESSAGE"]))
                        recs = queries.generate_topic_recommendations(session, selected_topic, topic_questions, fb_detail_all)
                    st.markdown(recs)

# ===== Tab 4: Conversation Inspector =======================================
with tab4:
    agents_df2 = queries.agent_list(session)
    if agents_df2.empty:
        st.info("No agents registered. Run simulate.py first.")
    else:
        agent4 = st.selectbox(
            "Select Agent",
            agents_df2["AGENT_NAME"].tolist(),
            key="inspector_agent",
        )
        days4 = st.slider("Lookback (days)", 1, 30, 7, key="inspector_days")

        traces = queries.agent_traces(session, agent4, days4)
        if traces.empty:
            st.info("No traces found for this agent in the selected timeframe.")
        else:
            trace_options = [
                f"{row['TRACE_ID'][:12]}... ({row['SPAN_COUNT']} calls, {row['FIRST_TS']})"
                for _, row in traces.iterrows()
            ]
            selected_idx = st.selectbox("Select Trace", range(len(trace_options)),
                                        format_func=lambda i: trace_options[i],
                                        key="trace_select")
            trace_id = traces.iloc[selected_idx]["TRACE_ID"]

            detail = queries.trace_detail(session, trace_id)
            if not detail.empty:
                # Summary metrics
                total_in = detail["INPUT_TOKENS"].sum()
                total_out = detail["OUTPUT_TOKENS"].sum()
                models_used = detail["MODEL"].dropna().unique().tolist()
                avg_latency = detail["LATENCY_SEC"].mean()

                mc1, mc2, mc3, mc4 = st.columns(4)
                mc1.metric("Gateway Calls", len(detail))
                mc2.metric("Total Tokens", f"{int(total_in + total_out):,}")
                mc3.metric("Model", ", ".join(models_used) if models_used else "N/A")
                mc4.metric("Avg Latency", f"{avg_latency:.1f}s" if avg_latency else "N/A")

                st.divider()

                # Extract the final span's output — that's the actual conversation
                # Earlier spans are intermediate reasoning steps; the last span has
                # the full accumulated context.
                last_span = detail.iloc[-1]

                # Show the user question (from the first span's first user message)
                first_span = detail.iloc[0]
                if first_span["INPUT_MESSAGES"]:
                    try:
                        in_msgs = json.loads(first_span["INPUT_MESSAGES"])
                        for m in in_msgs:
                            if m.get("role") == "user":
                                for p in m.get("parts", []):
                                    if "content" in p:
                                        st.markdown("**User**")
                                        st.info(p["content"])
                                        break
                                break
                    except (json.JSONDecodeError, TypeError):
                        pass

                # Build a map of tool_call_id → {name, args, response}
                tool_map = {}
                for _, span in detail.iterrows():
                    if span["OUTPUT_MESSAGES"]:
                        try:
                            for m in json.loads(span["OUTPUT_MESSAGES"]):
                                for p in m.get("parts", []):
                                    if p.get("type") == "tool_call" and "name" in p:
                                        cid = p.get("id", "")
                                        if cid and cid not in tool_map:
                                            tool_map[cid] = {
                                                "name": p["name"],
                                                "args": p.get("arguments", {}),
                                                "response": None,
                                            }
                        except (json.JSONDecodeError, TypeError):
                            pass
                    if span["INPUT_MESSAGES"]:
                        try:
                            for m in json.loads(span["INPUT_MESSAGES"]):
                                if m.get("role") == "tool":
                                    for p in m.get("parts", []):
                                        cid = p.get("id", "")
                                        if cid and cid in tool_map and "response" in p:
                                            tool_map[cid]["response"] = p["response"]
                        except (json.JSONDecodeError, TypeError):
                            pass

                if tool_map:
                    st.markdown(f"**Tools** ({len(tool_map)} call{'s' if len(tool_map) != 1 else ''})")
                    for cid, tc in tool_map.items():
                        with st.expander(f"{tc['name']}", expanded=False):
                            st.markdown("**Request**")
                            args_str = json.dumps(tc["args"], indent=2)
                            if len(args_str) > 500:
                                args_str = args_str[:500] + "..."
                            st.code(args_str, language="json")
                            if tc["response"] is not None:
                                st.markdown("**Response**")
                                resp_str = json.dumps(tc["response"], indent=2) if isinstance(tc["response"], (dict, list)) else str(tc["response"])
                                if len(resp_str) > 1000:
                                    resp_str = resp_str[:1000] + "..."
                                st.code(resp_str, language="json")

                # Show the final assistant response
                if last_span["OUTPUT_MESSAGES"]:
                    try:
                        out_msgs = json.loads(last_span["OUTPUT_MESSAGES"])
                        for m in out_msgs:
                            for p in m.get("parts", []):
                                if "content" in p and p["content"]:
                                    st.markdown("**Assistant**")
                                    st.success(p["content"])
                    except (json.JSONDecodeError, TypeError):
                        st.text(str(last_span["OUTPUT_MESSAGES"])[:500])

                # Per-call detail in a collapsible section
                with st.expander("Raw Gateway Calls", expanded=False):
                    for idx, (_, span) in enumerate(detail.iterrows()):
                        latency = f"{span['LATENCY_SEC']:.1f}s" if span["LATENCY_SEC"] else "N/A"
                        st.caption(
                            f"Call {idx + 1}: `{span['MODEL']}` | "
                            f"{span['INPUT_TOKENS']} in / {span['OUTPUT_TOKENS']} out | "
                            f"{latency} | HTTP {span['HTTP_STATUS']}"
                        )
