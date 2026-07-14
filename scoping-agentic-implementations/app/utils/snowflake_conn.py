import os
from snowflake.snowpark import Session


def get_session() -> Session:
    """Return a Snowpark session. Uses get_active_session() in SiS, falls back to env vars locally."""
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        pass

    connection_params = {
        "account": os.environ.get("SNOWFLAKE_ACCOUNT"),
        "user": os.environ.get("SNOWFLAKE_USER"),
        "password": os.environ.get("SNOWFLAKE_PASSWORD"),
        "role": os.environ.get("SNOWFLAKE_ROLE", "SYSADMIN"),
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "SCOPING_LAB_WH"),
        "database": os.environ.get("SNOWFLAKE_DATABASE", "SCOPING_LAB"),
        "schema": os.environ.get("SNOWFLAKE_SCHEMA", "PUBLIC"),
    }
    return Session.builder.configs(connection_params).create()
