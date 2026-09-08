-- Marketing Command Center Cortex Agent
-- Provides conversational analytics over demand forecasts, customer scores, and sales data

CREATE SCHEMA IF NOT EXISTS SB_COMMAND_CENTER.AGENTS;
CREATE SCHEMA IF NOT EXISTS SB_COMMAND_CENTER.PROCEDURES;

CREATE OR REPLACE AGENT SB_COMMAND_CENTER.AGENTS.MARKETING_COMMAND_CENTER
FROM SPECIFICATION $$
orchestration:
  budget:
    seconds: 60
    tokens: 32000
instructions:
  response: >
    You are the Marketing Command Center assistant for Summit Brands.
    Answer questions about demand forecasts, customer segments, POS sell-through,
    and marketing analytics. Be specific with numbers and actionable in recommendations.
    Key brands: Peak Hydro, ChefLine, Ridgeline, VitaCare, PrimeLine.
    Key retailers: Walmart, Target, Ulta, Home Depot, Kohls.
    Customer segments: Champion (highest value), Engaged, Moderate, At Risk.
  orchestration: >
    Use MarketingAnalyst for any data query about forecasts, sales, customers, or scores.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: MarketingAnalyst
      description: >
        Query demand forecasts, customer propensity scores, POS sell-through actuals,
        and omnichannel customer transactions for Summit Brands brands.
tool_resources:
  MarketingAnalyst:
    semantic_view: "SB_COMMAND_CENTER.SEMANTIC.MARKETING_COMMAND_CENTER_SV"
    execution_environment:
      type: warehouse
      warehouse: COMPUTE_WH
$$;
