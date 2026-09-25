# Gateway Analyzer

Streamlit app for analyzing **Cortex AI Gateway** traces. Reads the
OpenTelemetry spans the gateway emits and turns them into traffic, latency,
token, and routing views — the visual counterpart to the SQL in section 7 of the
[notebook](../cortex-ai-gateway-langchain-mcp.ipynb).

## Pages

| Page | Shows |
|---|---|
| **Overview** | Span and error volume by hour, token totals, model and caller distribution, and **trace grouping** — how many traces contain more than one span |
| **Model Performance** | Per-model p50 / p95 latency, output throughput (tokens/sec), error rate, and a caller × model matrix showing which workload routes where |
| **Caller Deep Dive** | One caller at a time: KPIs, models used, latency over time, and span-level detail with trace IDs |
| **Recommendations** | Seven rules evaluated against the observed spans — interactive workloads on slow models, elevated error rates, oversized responses, routing skew, missing `traceparent` propagation, and single-model dependencies |

The trace-grouping panel is the one worth demoing. A trace with several spans
means the client propagated a W3C `traceparent` header, so a multi-call agent
turn was recorded as one request. A window where every trace has exactly one
span means it did not, and the reasoning chain cannot be reconstructed — the
Recommendations page flags that explicitly.

## Prerequisites

**Gateway logging must be on.** `AGENT_TRACE_TABLE` is only populated when the
gateway spec sets `logging.enabled: true` — section 9 of [`../setup.sql`](../setup.sql)
does this. Verify with `SHOW AI GATEWAYS`.

**Privileges.** Reading the trace table needs only `MONITOR` on the gateway, so
the app does not require ACCOUNTADMIN:

```sql
CREATE ROLE IF NOT EXISTS AI_GATEWAY_MONITOR;
GRANT MONITOR ON AI GATEWAY SNOWFLAKE TO ROLE AI_GATEWAY_MONITOR;
GRANT USAGE ON WAREHOUSE GATEWAY_LAB_WH TO ROLE AI_GATEWAY_MONITOR;
GRANT ROLE AI_GATEWAY_MONITOR TO USER <you>;
```

**Gateway name.** The app reads `AGENT_TRACE_TABLE(<gateway>)` using the
`GATEWAY_NAME` constant in `streamlit_app.py`, which defaults to `SNOWFLAKE` —
the same object `../setup.sql` configures. Override with the `GATEWAY_NAME`
environment variable if your account exposes it under another name.

## Run it locally

```bash
SNOWFLAKE_DEFAULT_CONNECTION_NAME=<your-connection> \
  python3 -m streamlit run streamlit_app.py
```

Two wiring details that cost time if you get them wrong:

- Use **`SNOWFLAKE_DEFAULT_CONNECTION_NAME`**, not `SNOWFLAKE_CONNECTION_NAME`.
  The latter is the `snow` CLI variable; the Python connector behind
  `st.connection` reads the former.
- If the connection authenticates with a PAT, store it under the **`token`** key
  alongside `authenticator = "PROGRAMMATIC_ACCESS_TOKEN"`. Putting the PAT in
  `password` fails with `Programmatic access token is invalid`, which reads like
  a bad token rather than a misplaced key.

An SSO / `externalbrowser` connection works for local runs but will prompt
interactively, so it is unsuitable for headless use.

## Deploy to Snowflake

```bash
snow streamlit deploy --replace
```

`snowflake.yml` targets `GATEWAY_LAB_WH` (created by `../setup.sql`) and
`SYSTEM_COMPUTE_POOL_CPU`. Confirm afterwards:

```sql
SHOW STREAMLITS LIKE 'GATEWAY_ANALYZER' IN ACCOUNT;
```

## A note on the lab data

The lab in `../setup.sql` generates traces from a **single user** — whoever runs
the notebook. So the caller-oriented views (the Callers filter, the Caller Deep
Dive page, the caller × model matrix) will show exactly one entry, and the
routing and interactive-latency rules on the Recommendations page will not fire.

That is expected. Those views exist for real gateway traffic, where each
application or service account appears separately and the interesting question
is which workload routes to which model. To exercise them, point the app at an
account carrying real gateway traffic, or create a handful of service users with
their own PATs and drive a few requests through each.

## Theme

`.streamlit/config.toml` carries the Snowflake palette (primary `#29B5E8`).
Colors only — no bundled font files, so the app needs no static file serving.
