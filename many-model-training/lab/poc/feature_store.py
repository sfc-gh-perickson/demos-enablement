"""Feature Store integration for versioned feature management and reproducible experiments.

This module provides:
- setup_feature_store(): Registers entities and feature views (idempotent)
- get_feature_views(): Parses --features arg and returns registered FeatureView objects
- generate_training_dataset(): Creates versioned train/test datasets via Feature Store API
"""
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
from snowflake.snowpark import Window
from snowflake.ml.feature_store import FeatureStore, FeatureView, Entity
from typing import List, Tuple

try:
    from utils import (
        get_connection_config, get_feature_config,
        get_feature_store_config, get_fully_qualified_name
    )
except ImportError:
    from .utils import (
        get_connection_config, get_feature_config,
        get_feature_store_config, get_fully_qualified_name
    )

feature_cfg = get_feature_config()
fs_cfg = get_feature_store_config()
conn_cfg = get_connection_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]


def get_fs(session: Session) -> FeatureStore:
    """Return a FeatureStore instance for the configured schema."""
    return FeatureStore(
        session=session,
        database=conn_cfg["database"],
        name=fs_cfg["schema"],
        default_warehouse=conn_cfg["warehouse"],
        creation_mode="CREATE_IF_NOT_EXISTS",
    )


def setup_feature_store(session: Session):
    """Register entities and feature views in the Feature Store (idempotent).

    This creates:
    - Entity: STORE_ITEM (keyed by STORE_ITEM_ID)
    - FeatureView: DEMAND_BASE_FEATURES (calendar + event features)
    - FeatureView: DEMAND_WEATHER_FEATURES (weather data)
    - FeatureView: DEMAND_ROLLING_FEATURES (rolling aggregates)

    All feature views are external (refresh_freq=None) — they reference FEATURE_TABLE
    directly. This means zero additional compute cost; the feature views are simply
    views on top of the existing table.
    """
    fs = get_fs(session)
    feature_table_fqn = get_fully_qualified_name(feature_cfg["name"])

    # --- Entity ---
    entity = Entity(
        name=fs_cfg["entity_name"],
        join_keys=[fs_cfg["entity_key"]],
        desc="Store-item combination (e.g., S042_PIZZA)"
    )
    fs.register_entity(entity)
    print(f"   Entity registered: {fs_cfg['entity_name']}")

    # --- Feature Views ---
    for fv_name, fv_config in fs_cfg["feature_views"].items():
        fv_full_name = f"DEMAND_{fv_name.upper()}_FEATURES"
        columns = fv_config["columns"]

        # Build the source DataFrame: entity key + timestamp + feature columns
        select_cols = [GRAIN, TIME] + columns
        feature_df = session.table(feature_table_fqn).select(select_cols)

        fv = FeatureView(
            name=fv_full_name,
            entities=[entity],
            feature_df=feature_df,
            timestamp_col=TIME,
            refresh_freq=None,  # External: no auto-refresh, zero compute cost
            desc=fv_config.get("desc", f"{fv_name} features"),
        )

        fs.register_feature_view(
            feature_view=fv,
            version="v1",
            overwrite=True,
        )
        print(f"   FeatureView registered: {fv_full_name}/v1 ({len(columns)} features)")

    print(f"\n   Feature Store ready: {conn_cfg['database']}.{fs_cfg['schema']}")
    print(f"   Feature views: {list(fs_cfg['feature_views'].keys())}")


def get_feature_views(session: Session, feature_spec: str = None) -> List[FeatureView]:
    """Parse --features arg and return list of registered FeatureView objects.

    Args:
        feature_spec: Comma-separated list of "name/version" pairs.
                      e.g., "base/v1,weather/v1,rolling/v1"
                      If None, returns all configured feature views at v1.

    Returns:
        List of registered FeatureView objects ready for dataset generation.
    """
    fs = get_fs(session)

    if feature_spec is None:
        # Default: all configured feature views at v1
        specs = [(name, "v1") for name in fs_cfg["feature_views"].keys()]
    else:
        specs = []
        for item in feature_spec.split(","):
            parts = item.strip().split("/")
            name = parts[0]
            version = parts[1] if len(parts) > 1 else "v1"
            specs.append((name, version))

    feature_views = []
    for name, version in specs:
        fv_full_name = f"DEMAND_{name.upper()}_FEATURES"
        fv = fs.get_feature_view(fv_full_name, version)
        feature_views.append(fv)

    return feature_views


def generate_training_dataset(
    session: Session,
    feature_views: List[FeatureView],
    test_pct: float = None,
    table_prefix: str = "",
) -> Tuple:
    """Generate versioned train/test datasets via Feature Store.

    Creates a spine from FEATURE_TABLE (entity key + timestamp + label),
    joins with the specified feature views, and splits into train/test.

    Args:
        feature_views: List of FeatureView objects to include.
        test_pct: Fraction of data to hold out for testing. Defaults to config value.
        table_prefix: Prefix for output table names (e.g. "CHALLENGER_" -> CHALLENGER_TRAIN_DATA).
                      Empty string writes to TRAIN_DATA/TEST_DATA (champion default).

    Returns:
        (train_df, feature_metadata) tuple.
    """
    fs = get_fs(session)
    feature_table_fqn = get_fully_qualified_name(feature_cfg["name"])
    if test_pct is None:
        test_pct = feature_cfg["test_pct"]

    # Build spine: entity key + timestamp + label
    spine_df = session.table(feature_table_fqn).select(GRAIN, TIME, TARGET)

    # Generate training set using Feature Store (point-in-time correct join)
    full_df = fs.generate_training_set(
        spine_df=spine_df,
        features=feature_views,
        spine_timestamp_col=TIME,
        spine_label_cols=[TARGET],
    )

    # Collect feature metadata for reproducibility
    feature_metadata = {
        "feature_views": [
            {"name": fv.name, "version": fv.version}
            for fv in feature_views
        ],
        "feature_columns": [
            col for col in full_df.columns
            if col not in [GRAIN, TIME, TARGET]
        ],
    }

    # Train/test split by time within each partition
    partition_count = full_df.select(F.col(GRAIN)).distinct().count()
    print(f"   Generating dataset for {partition_count:,} partitions")
    print(f"   Feature views: {[f'{fv.name}/{fv.version}' for fv in feature_views]}")
    print(f"   Test percentage: {test_pct * 100:.0f}%")

    window_spec = Window.partition_by(F.col(GRAIN)).order_by(F.col(TIME))
    full_with_rank = full_df.with_column(
        "ROW_NUM", F.row_number().over(window_spec)
    )

    partition_counts = full_df.group_by(F.col(GRAIN)).agg(
        F.count("*").alias("PARTITION_COUNT")
    )

    full_with_split = full_with_rank.join(
        partition_counts, on=GRAIN
    ).with_column(
        "TRAIN_CUTOFF", F.floor(F.col("PARTITION_COUNT") * F.lit(1 - test_pct))
    ).with_column(
        "IS_TRAIN", F.col("ROW_NUM") <= F.col("TRAIN_CUTOFF")
    )

    columns_to_keep = [c for c in full_df.columns]

    train_df = full_with_split.filter(F.col("IS_TRAIN")).select(columns_to_keep)
    test_df = full_with_split.filter(~F.col("IS_TRAIN")).select(columns_to_keep)

    train_count = train_df.count()
    test_count = test_df.count()

    train_table = f"{table_prefix}TRAIN_DATA"
    test_table = f"{table_prefix}TEST_DATA"

    train_df.write.mode("overwrite").save_as_table(train_table)
    test_df.write.mode("overwrite").save_as_table(test_table)

    print(f"   Train rows: {train_count:,}")
    print(f"   Test rows: {test_count:,}")
    print(f"   Tables: {train_table}, {test_table}")

    return session.table(train_table), feature_metadata


if __name__ == "__main__":
    from utils import create_session

    session = create_session()
    print(f"Connected: {session.get_current_account()}")
    print("\nSetting up Feature Store...")
    setup_feature_store(session)
    print("\nDone.")
