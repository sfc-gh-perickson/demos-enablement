"""
Simulate three external agents sending queries through the Cortex AI Gateway.

Each agent uses a different model and sends ~15 queries (some multi-turn)
using MCP tools, producing traces in AGENT_TRACE_TABLE and usage records
in AI_GATEWAY_USAGE_HISTORY.

Mapping tables:
  GATEWAY_AGENTS        — agent metadata
  GATEWAY_AGENT_TRACES  — trace_id → agent_name
  GATEWAY_AGENT_FEEDBACK — simulated user feedback

Usage:
    python -m monitoring.simulate
"""

import asyncio
import os
import random
import tomllib
import uuid
from pathlib import Path

from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_openai import ChatOpenAI
from langchain_anthropic import ChatAnthropic
from langgraph.prebuilt import create_react_agent
import snowflake.connector

# ── Config ──────────────────────────────────────────────────────────────

CONNECTION_NAME = os.environ.get("SNOWFLAKE_CONNECTION_NAME", "parker_demo")

connections_path = Path.home() / ".snowflake" / "connections.toml"
if not connections_path.exists():
    connections_path = Path.home() / ".snowflake" / "cortex" / "agent" / "connections.toml"

with open(connections_path, "rb") as f:
    connections = tomllib.load(f)

conn_cfg = connections[CONNECTION_NAME]
SNOWFLAKE_ACCOUNT = conn_cfg["account"]
SNOWFLAKE_USER = conn_cfg["user"]
SNOWFLAKE_PAT = conn_cfg["password"]

SF_HOST = f"{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com".replace("_", "-")
INFERENCE_BASE_URL = f"https://{SF_HOST}/api/v2/aigateways/snowflake/v1"

MCP_HOST = SF_HOST
MCP_ENDPOINT = (
    f"https://{MCP_HOST}"
    f"/api/v2/databases/CORTEX_GATEWAY_LAB/schemas/PUBLIC/mcp-servers/MARKETING_MCP"
)

POSITIVE_FEEDBACK = [
    "Accurate numbers, exactly what I needed",
    "Well formatted table, easy to read",
    "Great breakdown by channel",
    "Correct methodology reference",
    "Helpful strategic context alongside data",
    "Fast and precise answer",
    "Good use of both data and strategy docs",
]

NEGATIVE_FEEDBACK = [
    "Too verbose, I wanted a concise answer",
    "Wrong metric — I asked for ROAS not ROI",
    "Missed the date range I specified",
    "Didn't break down by campaign as requested",
    "Numbers don't match what I see in the dashboard",
    "Should have used search docs for this, not SQL",
    "Response was too generic, no specific numbers",
    "Confused Q3 with Q4 data",
]

# Queries that should get negative feedback (edge cases / tricky requests)
NEGATIVE_QUERIES = {
    "Budget utilization vs plan — how are we tracking?",
    "How does our CPA compare to benchmarks?",
    "How does our CPA compare to industry benchmarks?",
    "What is our brand guidelines approach to campaign naming?",
    "Recommend channels to increase investment in based on data",
    "What are the risks of that allocation?",
    "Was that within our planned budget split?",
    "Compare email vs display conversion rates",
    "How does social media ROI compare to paid search?",
    "What is the click-through rate by channel?",
    "Which campaigns exceeded $50k in spend?",
    "Compare H1 vs H2 total marketing spend",
    "Which channels underperformed relative to benchmarks?",
    "What drove the increase — which channels grew most?",
    "Where did we underperform and what should we change?",
}

# Queries that get positive feedback
POSITIVE_QUERIES = {
    "What was Q4 ROAS by channel?",
    "Which campaign had the highest revenue in 2024?",
    "What was total marketing spend in 2024?",
    "Which channel drives the most conversions?",
    "Total spend by quarter for 2024?",
    "Which channel is most cost-efficient?",
    "What is our attribution methodology?",
    "Summarize the Q4 planning brief",
    "What are our performance benchmarks?",
    "Summarize key findings from all strategy documents",
    "Provide an executive summary of 2024 marketing performance",
    "Channel strategy recommendations based on 2024 data?",
}

# Everything else gets no feedback

# ── Agent definitions ───────────────────────────────────────────────────
# Each agent uses a different model to show model spread in the dashboard.

AGENTS = [
    {
        "name": "CMO Assistant",
        "model": "openai-gpt-5.4",
        "description": "Campaign analytics, ROAS, channel performance (GPT-5.4)",
        "system_prompt": (
            "You are a CMO Assistant specializing in campaign analytics and marketing "
            "performance. You help the Chief Marketing Officer analyze ROAS, channel "
            "performance, conversion rates, and campaign effectiveness.\n\n"
            "- For quantitative questions about campaign spend, revenue, ROI, etc.:\n"
            "  1. First call query_campaigns to generate the SQL query.\n"
            "  2. Extract the SQL statement from the response.\n"
            "  3. Then call execute_sql with that SQL to get the actual data rows.\n"
            "- For questions about strategy or methodology, use search_strategy_docs.\n"
            "- Always cite specific numbers when available. Express ROI as a multiplier "
            "(e.g., 3.2x). Round currency to 2 decimal places."
        ),
        "queries": [
            # Single-turn queries
            "What was Q4 ROAS by channel?",
            "Compare email vs display conversion rates",
            "Which campaign had the highest revenue in 2024?",
            "Show me monthly spend trends across all channels",
            "What is the cost per acquisition by channel for Q3?",
            "How does social media ROI compare to paid search?",
            "What was total marketing spend in 2024?",
            "Which channel drives the most conversions?",
            "What is the click-through rate by channel?",
            "Summarize overall marketing effectiveness for 2024",
            # Multi-turn conversations (list of lists)
            ["What was Q4 ROAS by channel?", "Which channel improved most vs Q3?"],
            ["Break down Q4 campaign performance", "How does Holiday Push compare to the planning brief targets?"],
            ["Show impressions vs clicks for display", "What's the conversion rate trend for display over the year?"],
        ],
    },
    {
        "name": "Finance Analyst",
        "model": "claude-sonnet-4-6",
        "description": "Budget tracking, spend analysis, cost efficiency (Claude Sonnet)",
        "system_prompt": (
            "You are a Finance Analyst focused on marketing budget tracking, spend "
            "analysis, and cost efficiency. You help the finance team understand where "
            "marketing dollars are going and whether spend is delivering value.\n\n"
            "- For quantitative questions about spend, budgets, cost efficiency:\n"
            "  1. First call query_campaigns to generate the SQL query.\n"
            "  2. Extract the SQL statement from the response.\n"
            "  3. Then call execute_sql with that SQL to get the actual data rows.\n"
            "- For questions about budget allocation strategy, use search_strategy_docs.\n"
            "- Always cite specific numbers. Round currency to 2 decimal places."
        ),
        "queries": [
            "Total spend by quarter for 2024?",
            "Which channel is most cost-efficient?",
            "What is the spend breakdown by campaign name?",
            "Show monthly spend for email campaigns only",
            "Which campaigns exceeded $50k in spend?",
            "What is the revenue-to-spend ratio by quarter?",
            "What are the budget allocation guidelines?",
            "Show the top 5 campaigns by spend",
            "What is the average monthly spend per channel?",
            "Summarize spend efficiency across all channels",
            # Multi-turn
            ["Total spend by quarter?", "How does that compare to our budget allocation targets?"],
            ["How much did we spend on social media in Q4?", "Was that within our planned budget split?"],
            ["Which quarter had the highest spend?", "What drove the increase — which channels grew most?"],
        ],
    },
    {
        "name": "Strategy Advisor",
        "model": "openai-gpt-5.4-mini",
        "description": "Market positioning, methodology, planning briefs (GPT-5.4 Mini)",
        "system_prompt": (
            "You are a Strategy Advisor helping leadership with market positioning, "
            "attribution methodology, and strategic planning. You combine data insights "
            "with strategic documents to provide actionable recommendations.\n\n"
            "- For quantitative questions:\n"
            "  1. First call query_campaigns to generate the SQL query.\n"
            "  2. Extract the SQL statement from the response.\n"
            "  3. Then call execute_sql with that SQL to get the actual data rows.\n"
            "- For strategy, methodology, or planning questions, use search_strategy_docs.\n"
            "- For questions needing both data and context, use both tools.\n"
            "- Always provide strategic context alongside numbers."
        ),
        "queries": [
            "What is our attribution methodology?",
            "Summarize the Q4 planning brief",
            "What are our performance benchmarks?",
            "What does our channel strategy document say about social media?",
            "What methodology do we use for revenue attribution?",
            "What is our approach to display advertising?",
            "Summarize key findings from all strategy documents",
            "How does our CPA compare to benchmarks?",
            "Provide an executive summary of 2024 marketing performance",
            "What is the recommended budget split for next year?",
            # Multi-turn
            ["Channel strategy recommendations based on 2024 data?", "Which channels should we increase investment in and why?"],
            ["Compare actual Q4 results to our benchmarks", "Where did we underperform and what should we change?"],
            ["How should we allocate budget for next quarter?", "What are the risks of that allocation?"],
        ],
    },
]

# ── Helpers ──────────────────────────────────────────────────────────────


def make_traceparent() -> tuple[str, str]:
    trace_id = uuid.uuid4().hex
    parent_id = uuid.uuid4().hex[:16]
    header = f"00-{trace_id}-{parent_id}-01"
    return header, trace_id


def make_llm(model: str, system_prompt: str, traceparent: str | None = None):
    headers = {}
    if traceparent:
        headers["traceparent"] = traceparent

    if model.startswith("claude"):
        # Anthropic Messages API — base_url without /v1 (SDK appends /v1/messages)
        auth_headers = {"Authorization": f"Bearer {SNOWFLAKE_PAT}"}
        auth_headers.update(headers)
        return ChatAnthropic(
            model=model,
            anthropic_api_url=f"https://{SF_HOST}/api/v2/aigateways/snowflake",
            anthropic_api_key="not-used",
            default_headers=auth_headers,
            temperature=0,
            max_tokens=4096,
        )
    else:
        # OpenAI Chat Completions API
        return ChatOpenAI(
            model=model,
            base_url=INFERENCE_BASE_URL,
            api_key=SNOWFLAKE_PAT,
            temperature=0,
            max_tokens=4096,
            default_headers=headers or None,
        )


def _get_sf_connection():
    return snowflake.connector.connect(
        account=SNOWFLAKE_ACCOUNT,
        user=SNOWFLAKE_USER,
        authenticator="PROGRAMMATIC_ACCESS_TOKEN",
        token=SNOWFLAKE_PAT,
        database="CORTEX_GATEWAY_LAB",
        schema="PUBLIC",
        warehouse="GATEWAY_LAB_WH",
    )


def register_agents():
    ctx = _get_sf_connection()
    try:
        cur = ctx.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENTS (
                AGENT_NAME VARCHAR,
                DESCRIPTION VARCHAR,
                REGISTERED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
        """)
        cur.execute("DELETE FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENTS")
        for agent in AGENTS:
            cur.execute(
                "INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENTS "
                "(AGENT_NAME, DESCRIPTION) VALUES (%s, %s)",
                (agent["name"], agent["description"]),
            )
            print(f"  Registered: {agent['name']} ({agent['model']})")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES (
                TRACE_ID VARCHAR,
                AGENT_NAME VARCHAR,
                CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
        """)
        cur.execute("DELETE FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK (
                TRACE_ID VARCHAR,
                AGENT_NAME VARCHAR,
                USER_MESSAGE VARCHAR,
                IS_POSITIVE BOOLEAN,
                FEEDBACK_MESSAGE VARCHAR,
                CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
        """)
        cur.execute("DELETE FROM CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK")

        cur.close()
    finally:
        ctx.close()


def record_trace(agent_name: str, trace_id: str):
    ctx = _get_sf_connection()
    try:
        cur = ctx.cursor()
        cur.execute(
            "INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_TRACES "
            "(TRACE_ID, AGENT_NAME) VALUES (%s, %s)",
            (trace_id, agent_name),
        )
        cur.close()
    finally:
        ctx.close()


def record_feedback(agent_name: str, trace_id: str, user_message: str):
    if user_message in NEGATIVE_QUERIES:
        is_positive = False
        msg = random.choice(NEGATIVE_FEEDBACK)
    elif user_message in POSITIVE_QUERIES:
        is_positive = True
        msg = random.choice(POSITIVE_FEEDBACK)
    else:
        return  # no feedback

    ctx = _get_sf_connection()
    try:
        cur = ctx.cursor()
        cur.execute(
            "INSERT INTO CORTEX_GATEWAY_LAB.PUBLIC.GATEWAY_AGENT_FEEDBACK "
            "(TRACE_ID, AGENT_NAME, USER_MESSAGE, IS_POSITIVE, FEEDBACK_MESSAGE) "
            "VALUES (%s, %s, %s, %s, %s)",
            (trace_id, agent_name, user_message[:500], is_positive, msg),
        )
        cur.close()
        symbol = "👍" if is_positive else "👎"
        print(f"           {symbol} {msg}")
    finally:
        ctx.close()


# ── Main simulation ─────────────────────────────────────────────────────


async def run_simulation():
    print("=" * 60)
    print("AI Gateway Simulation — 3 Agents, 3 Models, Multi-turn")
    print("=" * 60)

    print("\n[1/2] Registering agents in GATEWAY_AGENTS table...")
    register_agents()

    print("\n[2/2] Running agent queries through the gateway...\n")

    mcp_config = {
        "snowflake": {
            "transport": "http",
            "url": MCP_ENDPOINT,
            "headers": {"Authorization": f"Bearer {SNOWFLAKE_PAT}"},
        }
    }

    mcp_client = MultiServerMCPClient(mcp_config)
    tools = await mcp_client.get_tools()
    print(f"Loaded {len(tools)} MCP tools: {[t.name for t in tools]}\n")

    for agent_def in AGENTS:
        agent_name = agent_def["name"]
        model = agent_def["model"]
        system_prompt = agent_def["system_prompt"]
        query_list = agent_def["queries"]

        print(f"\n{'─' * 60}")
        print(f"Agent: {agent_name} | Model: {model} | {len(query_list)} queries")
        print(f"{'─' * 60}")

        for i, query_item in enumerate(query_list, 1):
            # Normalize: single query becomes [query], multi-turn is already a list
            turns = query_item if isinstance(query_item, list) else [query_item]
            is_multi = len(turns) > 1

            traceparent, trace_id = make_traceparent()
            messages = []

            for turn_idx, question in enumerate(turns):
                llm = make_llm(model, system_prompt, traceparent=traceparent)
                agent = create_react_agent(
                    model=llm,
                    tools=tools,
                    prompt=system_prompt,
                )

                turn_label = f"[{i}/{len(query_list)}]" if turn_idx == 0 else f"  ↳ follow-up"
                print(f"  {turn_label} {question}")
                if turn_idx == 0:
                    print(f"           trace={trace_id[:12]}... model={model}" + (" (multi-turn)" if is_multi else ""))

                messages.append({"role": "user", "content": question})

                try:
                    result = await agent.ainvoke({"messages": messages})
                    final = result["messages"][-1]
                    preview = final.content[:100].replace("\n", " ")
                    print(f"           → {preview}...")
                    messages = result["messages"]
                except Exception as e:
                    print(f"           ✗ Error: {e}")
                    break

            record_trace(agent_name, trace_id)
            record_feedback(agent_name, trace_id, turns[0])

    print(f"\n{'=' * 60}")
    print("Simulation complete!")
    print(f"{'=' * 60}")


if __name__ == "__main__":
    asyncio.run(run_simulation())
