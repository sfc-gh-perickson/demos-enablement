"""
Context-Scoped Cortex Agent Demo - Streamlit App

Shows a real analytics dashboard. The agent knows what the user is viewing
because context is injected into the messages behind the scenes.
"""

import streamlit as st
import pandas as pd
from agent_client import call_agent, extract_text_response

st.set_page_config(page_title="SaaS Analytics", layout="wide")

# ---------------------------------------------------------------------------
# Page and persona definitions
# ---------------------------------------------------------------------------

PAGES = ["Executive Dashboard", "Pipeline & Funnel", "Customer Segments"]

PERSONA_CONTEXTS = {
    "VP of Growth": {
        "User Role": "VP of Growth",
        "Focus Areas": "Revenue growth, churn reduction, user engagement",
    },
    "Head of Sales": {
        "User Role": "Head of Sales",
        "Focus Areas": "Pipeline velocity, conversion rates, deal size optimization",
    },
    "Customer Success Manager": {
        "User Role": "Customer Success Manager",
        "Focus Areas": "Retention, expansion revenue, customer health, NPS",
    },
}

PAGE_DATA = {
    "Executive Dashboard": {
        "Time Period": "Last 30 days (December 2024)",
        "Visible KPIs": "MRR $2.44M (+2.5% MoM), Churn Rate 3.8% (up from 3.6%), Active Users 18,200, NRR 101.2%",
        "Trend Alert": "Churn rate has increased for 6 consecutive months (2.1% to 3.8%)",
    },
    "Pipeline & Funnel": {
        "Time Period": "December 2024",
        "Selected Segment": "Enterprise",
        "Funnel Summary": "320 Awareness, 210 Interest (65.6%), 95 Evaluation (45.2%), 42 Negotiation (44.2%), 28 Closed Won (66.7%)",
        "Avg Deal Size": "$92,000 (Closed Won)",
        "Comparison": "vs November: Closed Won up from 24 to 28 (+16.7%), conversion from Negotiation improved from 63.2% to 66.7%",
    },
    "Customer Segments": {
        "Selected Segment": "Enterprise US West",
    },
}

# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------

st.sidebar.title("SaaS Analytics")
st.sidebar.markdown("---")

page = st.sidebar.radio("Dashboard:", PAGES, index=0)
st.sidebar.markdown("---")
persona = st.sidebar.radio("Persona:", list(PERSONA_CONTEXTS.keys()), index=0)

st.sidebar.markdown("---")
st.sidebar.caption(
    "The agent receives page + persona context as a system message. "
    "Try the same question with different combinations."
)

# Build the full context (page data + persona)
page_context = {"Page": page}
page_context.update(PAGE_DATA[page])
page_context.update(PERSONA_CONTEXTS[persona])

# ---------------------------------------------------------------------------
# Dashboard content
# ---------------------------------------------------------------------------

if page == "Executive Dashboard":
    st.title("Executive Dashboard")
    st.caption("December 2024")

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("MRR", "$2.44M", "+2.5%")
    c2.metric("Churn Rate", "3.8%", "+0.2%", delta_color="inverse")
    c3.metric("Active Users", "18,200", "+700")
    c4.metric("Net Revenue Retention", "101.2%", "-0.7%", delta_color="inverse")

    st.markdown("---")
    st.subheader("Monthly Trends")

    trend_data = pd.DataFrame({
        "Month": pd.date_range("2024-01-01", periods=12, freq="MS"),
        "MRR ($M)": [1.82, 1.88, 1.92, 1.98, 2.05, 2.10, 2.15, 2.20, 2.28, 2.32, 2.38, 2.44],
        "Churn Rate (%)": [2.1, 2.3, 2.0, 2.4, 2.6, 2.8, 3.0, 3.1, 3.3, 3.5, 3.6, 3.8],
    })

    col1, col2 = st.columns(2)
    with col1:
        st.caption("MRR Growth")
        st.line_chart(trend_data.set_index("Month")["MRR ($M)"])
    with col2:
        st.caption("Churn Rate (rising)")
        st.line_chart(trend_data.set_index("Month")["Churn Rate (%)"])

    st.warning("Churn rate has increased for 6 consecutive months (2.1% to 3.8%)")

elif page == "Pipeline & Funnel":
    st.title("Pipeline & Funnel")
    st.caption("December 2024 | Enterprise Segment")

    c1, c2, c3 = st.columns(3)
    c1.metric("Top of Funnel", "320 leads")
    c2.metric("Closed Won", "28 deals", "+16.7% vs Nov")
    c3.metric("Avg Deal Size", "$92,000")

    st.markdown("---")
    st.subheader("Conversion Funnel")

    funnel_data = pd.DataFrame({
        "Stage": ["Awareness", "Interest", "Evaluation", "Negotiation", "Closed Won"],
        "Leads": [320, 210, 95, 42, 28],
        "Conversion": ["100%", "65.6%", "45.2%", "44.2%", "66.7%"],
    })
    st.dataframe(funnel_data, use_container_width=True)

    st.bar_chart(
        pd.DataFrame({"Leads": [320, 210, 95, 42, 28]},
                     index=["Awareness", "Interest", "Evaluation", "Negotiation", "Closed Won"])
    )

elif page == "Customer Segments":
    st.title("Customer Segments")

    SEGMENTS = {
        "Enterprise US West": {"Customers": "85", "Retention": "96.2%", "NPS": "72.5", "Expansion": "12.4%", "Avg Deal": "$95,000", "Active Rate": "88.3%", "Top Feature": "Advanced Analytics", "Support": "2.1/mo"},
        "Enterprise US East": {"Customers": "110", "Retention": "94.8%", "NPS": "68.2", "Expansion": "10.8%", "Avg Deal": "$88,000", "Active Rate": "85.1%", "Top Feature": "Custom Dashboards", "Support": "3.4/mo"},
        "Enterprise EMEA": {"Customers": "62", "Retention": "93.5%", "NPS": "65.8", "Expansion": "9.2%", "Avg Deal": "$78,000", "Active Rate": "82.7%", "Top Feature": "Data Export", "Support": "4.2/mo"},
        "Mid-Market US": {"Customers": "245", "Retention": "91.2%", "NPS": "62.4", "Expansion": "7.5%", "Avg Deal": "$36,000", "Active Rate": "78.5%", "Top Feature": "Team Collaboration", "Support": "2.8/mo"},
        "Mid-Market EMEA": {"Customers": "180", "Retention": "89.8%", "NPS": "60.1", "Expansion": "6.8%", "Avg Deal": "$32,000", "Active Rate": "75.2%", "Top Feature": "Reporting", "Support": "3.5/mo"},
        "SMB US": {"Customers": "820", "Retention": "85.4%", "NPS": "58.2", "Expansion": "4.2%", "Avg Deal": "$11,500", "Active Rate": "68.4%", "Top Feature": "Basic Dashboards", "Support": "1.5/mo"},
        "SMB EMEA": {"Customers": "540", "Retention": "83.1%", "NPS": "55.8", "Expansion": "3.8%", "Avg Deal": "$10,200", "Active Rate": "64.2%", "Top Feature": "Basic Dashboards", "Support": "1.8/mo"},
        "SMB APAC": {"Customers": "320", "Retention": "81.5%", "NPS": "54.2", "Expansion": "3.2%", "Avg Deal": "$9,800", "Active Rate": "61.8%", "Top Feature": "Reporting", "Support": "2.2/mo"},
    }

    selected_segment = st.selectbox("Select Segment:", list(SEGMENTS.keys()))
    seg = SEGMENTS[selected_segment]

    st.caption(selected_segment)

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Customers", seg["Customers"])
    c2.metric("Retention", seg["Retention"])
    c3.metric("NPS", seg["NPS"])
    c4.metric("Expansion Revenue", seg["Expansion"])

    st.markdown("---")
    st.subheader("Segment Health")

    segment_data = pd.DataFrame({
        "Metric": ["Avg Deal Size", "Monthly Active Rate", "Top Feature", "Support Tickets"],
        "Value": [seg["Avg Deal"], seg["Active Rate"], seg["Top Feature"], seg["Support"]],
    })
    st.dataframe(segment_data, use_container_width=True)

    # Update page_context with the selected segment
    page_context["Selected Segment"] = selected_segment
    page_context["Segment Metrics"] = f"{seg['Customers']} customers, Avg deal {seg['Avg Deal']}, Retention {seg['Retention']}, NPS {seg['NPS']}, Monthly active {seg['Active Rate']}"
    page_context["Top Feature"] = seg["Top Feature"]
    page_context["Expansion Revenue"] = seg["Expansion"]
    page_context["Support Load"] = f"{seg['Support']} per customer"

# ---------------------------------------------------------------------------
# Agent chat
# ---------------------------------------------------------------------------

st.markdown("---")
st.subheader("Ask the Agent")

prompt = st.text_input("Ask a question about what you see:", key="agent_input")

if prompt:
    with st.spinner("Thinking..."):
        try:
            response = call_agent(prompt, page_context)
            text = extract_text_response(response)
        except Exception as e:
            text = f"Error: {e}"
    st.markdown("**Agent:**")
    st.markdown(text)
