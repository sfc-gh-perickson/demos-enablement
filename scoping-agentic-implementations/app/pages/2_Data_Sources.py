import streamlit as st
from utils.snowflake_conn import get_session

st.header("Step 2: Data Sources (Optional)")

st.info(
    "This step is optional. Skip it if you're scoping before data sources exist, "
    "working offline, or don't have access to the target Snowflake account yet. "
    "All downstream steps work without data source context."
)

if "data_sources" not in st.session_state:
    st.session_state.data_sources = {}

# --- Skip Option ---
if st.button("Skip — I'll configure data sources later"):
    st.session_state.data_sources = {}
    st.success("Skipped. Proceeding with generic context. You can return here anytime.")
    st.stop()

st.markdown("---")
st.markdown("**Connect to discover available data sources:**")

# --- Database/Schema Selection ---
col_db, col_schema = st.columns(2)

try:
    session = get_session()
    connected = True
except Exception as e:
    st.warning(f"Could not connect to Snowflake: {e}")
    st.markdown("You can skip this step and proceed without data source context.")
    connected = False
    st.stop()

with col_db:
    databases = [row[1] for row in session.sql("SHOW DATABASES").collect()]
    selected_db = st.selectbox("Database", databases, index=None, placeholder="Select a database")

with col_schema:
    if selected_db:
        schemas = [row[1] for row in session.sql(f"SHOW SCHEMAS IN {selected_db}").collect()]
        selected_schema = st.selectbox("Schema", schemas, index=None, placeholder="Select a schema")
    else:
        selected_schema = None
        st.selectbox("Schema", [], disabled=True, placeholder="Select database first")

if not selected_db or not selected_schema:
    st.stop()

fq_schema = f"{selected_db}.{selected_schema}"

# --- Discover Button ---
if st.button("Discover Data Sources", type="primary"):
    with st.spinner(f"Discovering objects in {fq_schema}..."):
        data_sources = {
            "database": selected_db,
            "schema": selected_schema,
            "semantic_views": [],
            "tables": [],
            "search_services": [],
        }

        # Semantic Views
        try:
            sv_rows = session.sql(f"SHOW SEMANTIC VIEWS IN {fq_schema}").collect()
            for row in sv_rows:
                sv_name = row[1]
                metrics = []
                dimensions = []
                try:
                    metric_rows = session.sql(f"SHOW SEMANTIC METRICS IN {fq_schema}.{sv_name}").collect()
                    for mr in metric_rows:
                        metrics.append({"name": mr[4], "description": mr[7] or ""})
                except Exception:
                    pass
                try:
                    dim_rows = session.sql(f"SHOW SEMANTIC DIMENSIONS IN {fq_schema}.{sv_name}").collect()
                    for dr in dim_rows:
                        dimensions.append({"name": dr[4], "description": dr[7] or ""})
                except Exception:
                    pass
                data_sources["semantic_views"].append({
                    "name": sv_name,
                    "fq_name": f"{fq_schema}.{sv_name}",
                    "metrics": metrics,
                    "dimensions": dimensions,
                })
        except Exception:
            pass

        # Tables
        try:
            tbl_rows = session.sql(f"SHOW TABLES IN {fq_schema}").collect()
            for row in tbl_rows:
                tbl_name = row[1]
                try:
                    col_rows = session.sql(f"DESCRIBE TABLE {fq_schema}.{tbl_name}").collect()
                    columns = [{"name": r[0], "type": r[1]} for r in col_rows]
                except Exception:
                    columns = []
                data_sources["tables"].append({"name": tbl_name, "fq_name": f"{fq_schema}.{tbl_name}", "columns": columns})
        except Exception:
            pass

        # Cortex Search Services
        try:
            ss_rows = session.sql(f"SHOW CORTEX SEARCH SERVICES IN {fq_schema}").collect()
            for row in ss_rows:
                ss_name = row[1]
                data_sources["search_services"].append({"name": ss_name, "fq_name": f"{fq_schema}.{ss_name}"})
        except Exception:
            pass

        st.session_state.data_sources = data_sources
        st.rerun()

# --- Display Discovered Sources ---
ds = st.session_state.data_sources
if ds:
    st.markdown("---")
    st.subheader("Discovered Data Sources")

    # Semantic Views
    svs = ds.get("semantic_views", [])
    st.markdown(f"**Semantic Views ({len(svs)})**")
    if svs:
        for sv in svs:
            with st.expander(f"{sv['name']} — {len(sv.get('metrics', []))} metrics, {len(sv.get('dimensions', []))} dimensions"):
                if sv.get("metrics"):
                    st.markdown("*Metrics:*")
                    for m in sv["metrics"]:
                        st.markdown(f"- `{m['name']}` — {m.get('description', '')}")
                if sv.get("dimensions"):
                    st.markdown("*Dimensions:*")
                    for d in sv["dimensions"]:
                        st.markdown(f"- `{d['name']}` — {d.get('description', '')}")
    else:
        st.caption("None found.")

    # Tables
    tables = ds.get("tables", [])
    st.markdown(f"**Tables ({len(tables)})**")
    if tables:
        for tbl in tables:
            with st.expander(f"{tbl['name']} — {len(tbl.get('columns', []))} columns"):
                if tbl.get("columns"):
                    import pandas as pd
                    st.dataframe(pd.DataFrame(tbl["columns"]), hide_index=True, use_container_width=True)
    else:
        st.caption("None found.")

    # Search Services
    ss = ds.get("search_services", [])
    st.markdown(f"**Cortex Search Services ({len(ss)})**")
    if ss:
        for s in ss:
            st.markdown(f"- `{s['name']}`")
    else:
        st.caption("None found.")

    st.success(f"Discovered: {len(svs)} semantic views, {len(tables)} tables, {len(ss)} search services")
