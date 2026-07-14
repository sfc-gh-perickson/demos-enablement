import streamlit as st

st.header("Step 5: Multi-Tenancy Assessment")
st.markdown("""
If your agent serves multiple user groups with different data access,
access control must be scoped into the agent spec from the start.
""")

if "tenancy_spec" not in st.session_state:
    st.session_state.tenancy_spec = {}

multi_tenant = st.toggle("Will multiple user groups share this agent with different data access?", value=bool(st.session_state.tenancy_spec))

if not multi_tenant:
    st.info("Single-tenant: all users see the same data. No additional access control needed in the agent spec.")
    st.session_state.tenancy_spec = {}
    st.stop()

st.markdown("---")
st.subheader("Tenant Model")

tenant_model = st.radio(
    "How are tenants structured?",
    ["multi-tenant-internal (teams/departments with Snowflake accounts)",
     "multi-tenant-external (customers/partners without Snowflake accounts)"],
    index=0,
)

tenant_count = st.text_input("Approximate number of tenants", value=st.session_state.tenancy_spec.get("tenant_count", ""))

st.markdown("---")
st.subheader("Identity & Session Attributes")

identity_mechanism = st.selectbox(
    "How will tenant identity be determined?",
    ["Immutable session attributes (recommended for external)", "Snowflake roles (internal teams)", "App-layer filtering (not recommended)"],
    index=0,
)

session_attrs = st.text_area(
    "Session attributes to pass (one per line)",
    value=st.session_state.tenancy_spec.get("session_attributes", "tenant_id\nuser_role"),
    help="These are passed by your application when calling the agent API",
)

st.markdown("---")
st.subheader("Data Access Policies")

rap_tables = st.text_area(
    "Tables needing Row Access Policies (one per line, with filter column)",
    value=st.session_state.tenancy_spec.get("rap_tables", ""),
    placeholder="SALES_DATA (filter by REGION)\nCUSTOMERS (filter by OWNER_TENANT_ID)",
)

masked_columns = st.text_area(
    "Columns needing masking (one per line)",
    value=st.session_state.tenancy_spec.get("masked_columns", ""),
    placeholder="SALARY (full for managers, NULL for others)\nSSN (always masked)",
)

st.markdown("---")
st.subheader("Cortex Search Considerations")

uses_search = st.toggle("Does the agent use Cortex Search for document retrieval?")
search_approach = ""
if uses_search:
    st.warning("Row Access Policies do NOT apply to Cortex Search. You need a tenancy strategy for search.")
    search_approach = st.radio(
        "Search tenancy approach",
        ["Per-tenant search service (works for <10 tenants)",
         "Pre-filtered source tables (one table per tenant, rebuild index)",
         "Shared search with post-retrieval filtering in agent instructions (not secure)"],
    )

# Store spec
st.session_state.tenancy_spec = {
    "tenant_model": tenant_model,
    "tenant_count": tenant_count,
    "identity_mechanism": identity_mechanism,
    "session_attributes": session_attrs,
    "rap_tables": rap_tables,
    "masked_columns": masked_columns,
    "uses_search": uses_search,
    "search_approach": search_approach,
}

# Summary
st.markdown("---")
st.subheader("Access Control Summary")
st.json(st.session_state.tenancy_spec)
