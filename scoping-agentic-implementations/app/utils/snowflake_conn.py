import os
from snowflake.snowpark import Session


def get_session() -> Session:
    """Return a Snowpark session.

    Tries in order:
    1. get_active_session() (Streamlit-in-Snowflake)
    2. Default Snowflake connection (from ~/.snowflake/connections.toml)
    3. Environment variables (SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD)
    """
    # 1. SiS active session
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        pass

    # 2. Default connection (connections.toml or SNOWFLAKE_DEFAULT_CONNECTION_NAME)
    try:
        return Session.builder.create()
    except Exception:
        pass

    # 3. Explicit env vars
    account = os.environ.get("SNOWFLAKE_ACCOUNT")
    user = os.environ.get("SNOWFLAKE_USER")
    password = os.environ.get("SNOWFLAKE_PASSWORD")

    if not account or not user:
        raise ConnectionError(
            "No Snowflake connection available. Configure one of:\n"
            "  1. Run in Streamlit-in-Snowflake (automatic)\n"
            "  2. Set up ~/.snowflake/connections.toml (default connection)\n"
            "  3. Set SNOWFLAKE_ACCOUNT + SNOWFLAKE_USER + SNOWFLAKE_PASSWORD env vars"
        )

    connection_params = {
        "account": account,
        "user": user,
        "password": password,
        "role": os.environ.get("SNOWFLAKE_ROLE", "SYSADMIN"),
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "SCOPING_LAB_WH"),
        "database": os.environ.get("SNOWFLAKE_DATABASE", "SCOPING_LAB"),
        "schema": os.environ.get("SNOWFLAKE_SCHEMA", "PUBLIC"),
    }
    return Session.builder.configs(connection_params).create()
