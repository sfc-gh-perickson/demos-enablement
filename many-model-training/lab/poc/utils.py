"""Utilities for config loading, session creation, and stage operations."""
import yaml
from pathlib import Path
from snowflake.snowpark import Session

_config = None


def load_config(config_path: str = None) -> dict:
    """Load and cache configuration from YAML file."""
    global _config
    if _config is None:
        if config_path is None:
            config_path = Path(__file__).parent / "config.yaml"
        with open(config_path, "r") as f:
            _config = yaml.safe_load(f)
    return _config


def get_connection_config() -> dict:
    """Return connection settings from config."""
    return load_config()["connection"]


def get_feature_config() -> dict:
    """Return feature details from config."""
    return load_config()["feature_table"]


def get_training_config() -> dict:
    """Return training parameters from config."""
    cfg = load_config()["training"]
    cfg["compute_pool_name"] = f"MMT_DEMO_TRAIN_{cfg['instance_family']}_{cfg['target_cluster_size']}"
    return cfg


def get_inference_config() -> dict:
    """Return inference parameters from config."""
    return load_config()["inference"]


def get_telemetry_config() -> dict:
    """Return telemetry settings from config (drift detection, retrain triggers)."""
    return load_config()["telemetry"]


def get_experiment_config() -> dict:
    """Return experiment settings from config (champion/challenger parameters)."""
    return load_config()["experiment"]


def get_feature_store_config() -> dict:
    """Return feature store settings from config."""
    return load_config()["feature_store"]


def get_fully_qualified_name(table_name: str) -> str:
    """Return DATABASE.SCHEMA.table_name from config."""
    conn_cfg = get_connection_config()
    return f"{conn_cfg['database']}.{conn_cfg['schema']}.{table_name}"


def get_stage_path(subpath: str = "") -> str:
    """Build fully qualified stage path with optional subpath suffix."""
    conn_cfg = get_connection_config()
    base = f"@{conn_cfg['database']}.{conn_cfg['schema']}.{conn_cfg['stage_artifacts']}"
    if subpath:
        return f"{base}/{subpath}"
    return base


def create_session(query_tag: str = "") -> Session:
    """Create and configure a Snowpark session using config settings."""
    conn_cfg = get_connection_config()
    session = Session.builder.getOrCreate()
    session.use_database(conn_cfg['database'])
    session.use_schema(conn_cfg['schema'])
    session.use_warehouse(conn_cfg['warehouse'])
    if query_tag:
        session.sql(f"ALTER SESSION SET QUERY_TAG = '{query_tag}'").collect()
    return session


def stage_data_partitioned(session: Session, source_table: str, stage_subpath: str, 
                           partition_col:str):
    """COPY table to stage as partitioned parquet files."""
    stage_path = get_stage_path(stage_subpath)
    fqn = get_fully_qualified_name(source_table)
    
    session.sql(f"REMOVE {stage_path}/").collect()
    session.sql(f"""
        COPY INTO {stage_path}/
        FROM {fqn}
        PARTITION BY {partition_col}
        FILE_FORMAT = (TYPE = PARQUET COMPRESSION = SNAPPY)
        MAX_FILE_SIZE = 15728640
        HEADER = TRUE
    """).collect()
    session.sql(f"LIST {stage_path}/").show()


def copy_from_stage_to_table(session: Session, table_name: str, stage_subpath: str,
                              pattern: str = ".*[.]parquet", truncate_first: bool = True):
    """COPY parquet files from stage into table."""
    stage_path = get_stage_path(stage_subpath)
    table_name = get_fully_qualified_name(table_name)
    
    if truncate_first:
        session.sql(f"TRUNCATE TABLE IF EXISTS {table_name}").collect()
    
    session.sql(f"""
        COPY INTO {table_name}
        FROM {stage_path}/
        FILE_FORMAT = (TYPE = PARQUET COMPRESSION = SNAPPY)
        PATTERN = '{pattern}'
        MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    """).collect()
