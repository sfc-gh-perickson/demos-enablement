"""Many Model Training pipeline with champion/challenger experiment support.

Supports both champion and challenger modes via CLI arguments:
  python train.py                           # Champion (default)
  python train.py --mode challenger \\
    --version v_challenger_conservative \\
    --hyperparams '{"n_estimators":100,"max_depth":4,"learning_rate":0.05}' \\
    --run-experiment
"""
from snowflake.snowpark import Session
from snowflake.snowpark import functions as F
from snowflake.ml.data.data_connector import DataConnector
from snowflake.ml.modeling.distributors.many_model import ManyModelTraining, PickleSerde
from register import register_model
from feature_store import get_feature_views, generate_training_dataset

from datetime import datetime
import argparse
import json
import pandas as pd
from utils import (
    get_training_config, get_feature_config, get_telemetry_config,
    create_session, get_stage_path,
    stage_data_partitioned, copy_from_stage_to_table,
    get_fully_qualified_name
)

train_cfg = get_training_config()
feature_cfg = get_feature_config()
telemetry_cfg = get_telemetry_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]
EXCLUDE_COLS = [GRAIN, TARGET, TIME]

# Default champion hyperparams
DEFAULT_HYPERPARAMS = {
    "n_estimators": 200,
    "max_depth": 6,
    "learning_rate": 0.1,
    "eval_metric": "mae",
}

# Module-level hyperparams — set from CLI args before training starts.
# Workers read this at import time since ManyModelTraining serializes the function.
HYPERPARAMS = DEFAULT_HYPERPARAMS.copy()


def train_partition(data_connector: DataConnector, context):
    """DPF worker: train XGBoost model with SHAP explainability and validation metrics."""
    import pandas as pd
    import numpy as np
    import json
    from datetime import datetime
    from xgboost import XGBRegressor
    import shap

    df = data_connector.to_pandas()
    if df.empty:
        return None

    feature_cols = [c for c in df.columns if c not in EXCLUDE_COLS]

    # Split into train/validation (80/20) for honest metrics
    split_idx = int(len(df) * 0.8)
    train_df = df.iloc[:split_idx]
    val_df = df.iloc[split_idx:]

    X_train = train_df[feature_cols].astype("float32")
    y_train = train_df[TARGET].astype("float32")
    X_val = val_df[feature_cols].astype("float32")
    y_val = val_df[TARGET].astype("float32")

    # Train model using configured hyperparams
    model = XGBRegressor(
        n_estimators=HYPERPARAMS.get("n_estimators", 200),
        max_depth=HYPERPARAMS.get("max_depth", 6),
        learning_rate=HYPERPARAMS.get("learning_rate", 0.1),
        eval_metric=HYPERPARAMS.get("eval_metric", "mae"),
    )
    model.fit(
        X_train, y_train,
        eval_set=[(X_val, y_val)],
        verbose=False
    )

    # Training metrics
    train_pred = model.predict(X_train)
    train_mae = float(np.mean(np.abs(y_train - train_pred)))
    train_rmse = float(np.sqrt(np.mean((y_train - train_pred) ** 2)))

    # Validation metrics
    val_pred = model.predict(X_val)
    val_mae = float(np.mean(np.abs(y_val - val_pred)))
    val_rmse = float(np.sqrt(np.mean((y_val - val_pred) ** 2)))
    val_mape = float(np.mean(np.abs((y_val - val_pred) / np.maximum(y_val, 1.0))))

    # Feature importances (native XGBoost gain-based)
    feature_importances = {feat: float(imp) for feat, imp in zip(feature_cols, model.feature_importances_)}

    # SHAP values for explainability
    try:
        explainer = shap.TreeExplainer(model)
        shap_values = explainer.shap_values(X_val)
        mean_abs_shap = {feat: float(val) for feat, val in
                        zip(feature_cols, np.abs(shap_values).mean(axis=0))}
        sample_explanations = []
        for i in range(min(5, len(X_val))):
            explanation = {feat: float(shap_values[i][j]) for j, feat in enumerate(feature_cols)}
            explanation["_base_value"] = float(explainer.expected_value)
            explanation["_prediction"] = float(val_pred[i])
            sample_explanations.append(explanation)
    except Exception:
        mean_abs_shap = feature_importances
        sample_explanations = []

    # Prediction interval based on residual std
    residual_std = float(np.std(y_val - val_pred))

    best_iter = getattr(model, "best_iteration", None)

    metrics = {
        "TRAIN_MAE": train_mae,
        "TRAIN_RMSE": train_rmse,
        "TRAIN_ROWS": int(len(train_df)),
        "VAL_MAE": val_mae,
        "VAL_RMSE": val_rmse,
        "VAL_MAPE": val_mape,
        "VAL_ROWS": int(len(val_df)),
        "FEATURE_IMPORTANCES": feature_importances,
        "SHAP_IMPORTANCES": mean_abs_shap,
        "SAMPLE_EXPLANATIONS": sample_explanations,
        "RESIDUAL_STD": residual_std,
        "N_ESTIMATORS_USED": int(best_iter + 1) if best_iter is not None else HYPERPARAMS.get("n_estimators", 200),
        "HYPERPARAMS": HYPERPARAMS,
    }

    partition_id = context.partition_id

    metrics_df = pd.DataFrame([{
        "PARTITION_ID": partition_id,
        "TRAINED_AT": datetime.utcnow().isoformat(),
        "METRICS": metrics,
    }])

    context.upload_to_stage(metrics_df, "metrics.parquet",
                            write_function=lambda pdf, path: pdf.to_parquet(path, index=False))
    return model


def get_train_version() -> str:
    """Generate timestamped version string (e.g., v20240315_1430)."""
    return datetime.utcnow().strftime("v%Y%m%d_%H%M")


def prepare_data(session: Session, feature_spec: str = None, table_prefix: str = ""):
    """Generate train/test datasets via Feature Store.

    Uses the Feature Store to assemble a versioned, point-in-time correct dataset
    from the specified feature views. This ensures reproducibility — every training
    run records exactly which feature view versions were used.

    Args:
        feature_spec: Comma-separated "name/version" pairs (e.g. "base/v1,weather/v1").
                      If None, uses all configured feature views at v1.
        table_prefix: Prefix for output tables (e.g. "CHALLENGER_" -> CHALLENGER_TRAIN_DATA).

    Returns:
        (train_df, feature_metadata) where feature_metadata records which features were used.
    """
    print(f"\n   Generating dataset from Feature Store...")
    feature_views = get_feature_views(session, feature_spec)
    train_df, feature_metadata = generate_training_dataset(session, feature_views, table_prefix=table_prefix)
    return train_df, feature_metadata


def execute_training(session: Session, train_run_id: str, train_df):
    """Run ManyModelTraining from a Snowpark DataFrame."""
    stage_path = get_stage_path()
    trainer = ManyModelTraining(
        train_func=train_partition,
        stage_name=stage_path.replace("@", ""),
        serde=PickleSerde(),
    )

    train_run = trainer.run(
        partition_by=GRAIN,
        snowpark_dataframe=train_df,
        run_id=train_run_id,
        on_existing_artifacts="overwrite",
    )

    train_status = train_run.wait()
    print(f"\n   Training status: {train_status}")
    return train_run


def collect_training_metrics(session: Session, train_run_id: str, from_stage: bool = False):
    """Load metrics parquet files from stage into MODEL_STAGING table."""
    session.sql("""
        CREATE OR REPLACE TEMPORARY TABLE MODEL_STAGING (
            PARTITION_ID VARCHAR(200),
            TRAINED_AT DATE,
            METRICS VARIANT
        );
    """).collect()
    # When training from stage (challenger), metrics are written under {run_id}/train_features/
    stage_subpath = f"{train_run_id}/train_features" if from_stage else f"{train_run_id}"
    copy_from_stage_to_table(session, "MODEL_STAGING", stage_subpath, truncate_first=True)


def update_model_catalog(session: Session, train_version: str, train_run_id: str,
                         is_active: bool = True, write_mode: str = "overwrite",
                         feature_metadata: dict = None):
    """Persist per-partition training metrics and stage paths into MODEL_CATALOG.

    Args:
        is_active: Whether models should be marked as active (champion=True, challenger=False).
        write_mode: "overwrite" replaces MODEL_CATALOG; "append" adds entries (deletes previous
                    entries for this version first).
        feature_metadata: Dict recording which feature views/versions were used (for reproducibility).
    """
    print(f"\n   Updating MODEL_CATALOG (mode={write_mode}, is_active={is_active})...")

    stage_path = get_stage_path()
    fq_str = ".".join(stage_path.split(".")[:-1])
    catalog_fqn = get_fully_qualified_name("MODEL_CATALOG")

    metrics_df = session.table("MODEL_STAGING")

    # Enrich METRICS column with feature metadata for reproducibility
    if feature_metadata and feature_metadata.get("feature_views"):
        feature_info = json.dumps(feature_metadata)
        catalog_df = metrics_df.with_columns(
            ["MODEL_VERSION", "IS_ACTIVE", "METRICS"],
            [
                F.lit(train_version),
                F.lit(is_active),
                F.call_function("OBJECT_INSERT",
                    F.col("METRICS"),
                    F.lit("FEATURE_METADATA"),
                    F.parse_json(F.lit(feature_info))
                )
            ]
        )
    else:
        catalog_df = metrics_df.with_columns(
            ["MODEL_VERSION", "IS_ACTIVE"],
            [F.lit(train_version), F.lit(is_active)]
        )

    artifact_rows = session.sql(f"LIST '{stage_path}/{train_run_id}'").collect()

    subdir_to_model_path = []
    for row in artifact_rows:
        raw_name = row["name"]
        if raw_name.endswith("/model.pkl"):
            model_dir = raw_name.rsplit("/", 1)[0]
            parts = model_dir.split("/")
            subdir = parts[-1]
            subdir_to_model_path.append((subdir, f"{fq_str}.{model_dir}"))

    if not subdir_to_model_path:
        print("   WARNING: No model artifacts found on stage!")
        return

    paths = session.create_dataframe(
        pd.DataFrame(subdir_to_model_path, columns=["PARTITION_ID", "STAGE_PATH"])
    )
    catalog_df = catalog_df.join(paths, on="PARTITION_ID")

    # Ensure consistent column order matching MODEL_CATALOG schema
    catalog_df = catalog_df.select("PARTITION_ID", "TRAINED_AT", "METRICS",
                                   "MODEL_VERSION", "IS_ACTIVE", "STAGE_PATH")

    if write_mode == "append":
        # Ensure PARTITION_ID column is wide enough (may have been created with VARCHAR(20))
        session.sql(f"ALTER TABLE {catalog_fqn} ALTER COLUMN PARTITION_ID SET DATA TYPE VARCHAR(200)").collect()
        # Delete previous entries for this version before appending
        session.sql(f"""
            DELETE FROM {catalog_fqn}
            WHERE MODEL_VERSION = '{train_version}'
        """).collect()
        # Write to temp table first, then INSERT with explicit column names to avoid type mismatch
        catalog_df.write.mode("overwrite").save_as_table("MODEL_CATALOG_STAGING", table_type="temporary")
        session.sql(f"""
            INSERT INTO {catalog_fqn} (PARTITION_ID, TRAINED_AT, METRICS, MODEL_VERSION, IS_ACTIVE, STAGE_PATH)
            SELECT PARTITION_ID, TRAINED_AT, METRICS::VARIANT, MODEL_VERSION, IS_ACTIVE, STAGE_PATH
            FROM MODEL_CATALOG_STAGING
        """).collect()
    else:
        catalog_df.write.mode("overwrite").save_as_table("MODEL_CATALOG")

    print(f"   {catalog_df.count()} partitions saved to MODEL_CATALOG")


def run_challenger_inference(session: Session, challenger_version: str, use_challenger_data: bool = False):
    """Run inference with challenger models and store in CHALLENGER_PREDICTIONS.
    
    Args:
        challenger_version: Version string of the challenger model to run inference with.
        use_challenger_data: If True, reads from CHALLENGER_TEST_DATA (feature-set experiment).
                            If False, reads from TEST_DATA (hyperparams-only experiment).
    """
    from snowflake.ml.modeling.distributors.many_model import PickleSerde
    from snowflake.ml.modeling.distributors.distributed_partition_function.dpf import DPF

    test_table = "CHALLENGER_TEST_DATA" if use_challenger_data else "TEST_DATA"
    print(f"\n   Running challenger inference (test data: {test_table})...")

    catalog_fqn = get_fully_qualified_name("MODEL_CATALOG")
    predictions_fqn = get_fully_qualified_name("CHALLENGER_PREDICTIONS")

    session.sql(f"""
        CREATE TABLE IF NOT EXISTS {predictions_fqn} (
            {GRAIN} VARCHAR(200),
            {TIME} TIMESTAMP_NTZ,
            {TARGET} FLOAT,
            PREDICTION FLOAT
        )
    """).collect()

    serde = PickleSerde()

    # Join test data with challenger model paths
    test_data = session.table(test_table)
    challenger_catalog = session.table(catalog_fqn).filter(
        F.col("MODEL_VERSION") == challenger_version
    ).select(F.col("PARTITION_ID").alias(GRAIN), "STAGE_PATH")

    infer_data = test_data.join(challenger_catalog, on=GRAIN)
    infer_data.write.mode("overwrite").save_as_table("CHALLENGER_INFER_TRANSIENT", table_type="temporary")

    stage_data_partitioned(session, "CHALLENGER_INFER_TRANSIENT", "challenger_infer", partition_col=GRAIN)

    def predict_partition(data_connector, context):
        import pandas as pd
        import numpy as np

        df = data_connector.to_pandas()
        if df.empty:
            return None

        model_path = df["STAGE_PATH"].unique()[0]
        model = context.download_from_stage(
            serde.filename,
            stage_path=model_path,
            read_function=serde.read,
        )

        df = df.sort_values(TIME)
        X = df[model.feature_names_in_].astype("float32")
        preds = model.predict(X)

        out = df[[GRAIN, TIME, TARGET]].copy()
        out["PREDICTION"] = preds

        context.upload_to_stage(out, "predictions.parquet",
            write_function=lambda pdf, path: pdf.to_parquet(path, index=False))

    inference_run_id = f"challenger_inference_{datetime.utcnow().strftime('%Y%m%d_%H%M')}"
    dpf = DPF(predict_partition, get_stage_path())
    inf_run = dpf.run_from_stage(
        stage_location=get_stage_path("challenger_infer"),
        run_id=inference_run_id,
        on_existing_artifacts="overwrite",
    )
    inf_status = inf_run.wait()
    print(f"   Challenger inference status: {inf_status}")

    copy_from_stage_to_table(session, predictions_fqn.split(".")[-1], f"{inference_run_id}/challenger_infer")
    print(f"   Challenger predictions written to CHALLENGER_PREDICTIONS")


def run_champion_inference(session: Session):
    """Run inference with the registered champion model on TEST_DATA → FORECAST_TELEMETRY.
    Builds the telemetry table with real predictions, actuals, and monitoring columns."""
    from infer import score_test_data
    print("\n   Running champion inference on TEST_DATA...")
    count = score_test_data(session)
    print(f"   Champion predictions written: {count:,}")

    # Build FORECAST_TELEMETRY from real inference results
    print("   Building FORECAST_TELEMETRY from real predictions...")
    session.sql(f"""
        CREATE OR REPLACE TABLE FORECAST_TELEMETRY AS
        WITH base AS (
            SELECT
                STORE_ITEM_ID, TS,
                PREDICTION AS PREDICTED,
                DEMAND AS ACTUAL,
                DEMAND - PREDICTION AS ERROR,
                ABS(DEMAND - PREDICTION) AS ABS_ERROR,
                ABS(DEMAND - PREDICTION) / GREATEST(DEMAND, 1.0) AS PCT_ERROR
            FROM PREDICTIONS
            WHERE DEMAND IS NOT NULL
        ),
        with_rolling AS (
            SELECT *,
                AVG(PCT_ERROR) OVER (
                    PARTITION BY STORE_ITEM_ID ORDER BY TS
                    ROWS BETWEEN 167 PRECEDING AND CURRENT ROW
                ) AS ROLLING_7D_MAPE
            FROM base
        )
        SELECT
            STORE_ITEM_ID, TS, PREDICTED, ACTUAL, ERROR, ABS_ERROR, PCT_ERROR,
            ROLLING_7D_MAPE,
            CASE WHEN ROLLING_7D_MAPE > {telemetry_cfg['drift_threshold_mape']} THEN TRUE ELSE FALSE END AS DRIFT_FLAG
        FROM with_rolling
    """).collect()

    # Drop intermediate PREDICTIONS table
    session.sql("DROP TABLE IF EXISTS PREDICTIONS").collect()
    print(f"   FORECAST_TELEMETRY ready (PREDICTIONS merged in)")


def run_real_experiment(session: Session, challenger_version: str):
    """Compare champion vs challenger predictions against real DEMAND from TEST_DATA.

    Logs to Snowflake ExperimentTracking (visible in Snowsight AI & ML > Experiments).
    """
    from experiment import run_experiment
    import numpy as np

    print("=" * 60)
    print("CHAMPION VS CHALLENGER EXPERIMENT")
    print("=" * 60)

    champion_version = session.sql(
        "SELECT MODEL_VERSION FROM MODEL_CATALOG WHERE IS_ACTIVE = TRUE LIMIT 1"
    ).collect()[0]["MODEL_VERSION"]

    telemetry_fqn = get_fully_qualified_name("FORECAST_TELEMETRY")
    challenger_fqn = get_fully_qualified_name("CHALLENGER_PREDICTIONS")

    # Champion predictions + actuals from FORECAST_TELEMETRY
    champion_df = session.table(telemetry_fqn).select(
        GRAIN, TIME, F.col("ACTUAL"), F.col("PREDICTED")
    ).to_pandas()

    # Challenger predictions from real inference
    challenger_df = session.table(challenger_fqn).select(
        GRAIN, TIME, F.col("PREDICTION").alias("CHALLENGER_PRED")
    ).to_pandas()

    # Merge
    merged = champion_df.merge(challenger_df, on=[GRAIN, TIME], how="inner")

    if merged.empty:
        print("   No overlapping predictions found. Check that both inference runs cover the same time range.")
        return None, {}

    # Pass merged challenger predictions to the experiment tracker
    challenger_preds = merged[[GRAIN, TIME, "CHALLENGER_PRED"]]

    run_name, summary = run_experiment(
        session,
        champion_version=champion_version,
        challenger_version=challenger_version,
        challenger_predictions=challenger_preds,
        challenger_hyperparams=HYPERPARAMS,
        description=f"Challenger ({challenger_version}) vs Champion ({champion_version})"
    )

    return run_name, summary


def run_training(session: Session, mode: str = "champion", version: str = None,
                 is_active: bool = True, write_mode: str = "overwrite",
                 feature_spec: str = None):
    """Entry point: prepare data, train models, update catalog.

    Args:
        mode: "champion" prepares fresh data; "challenger" reuses existing TRAIN_DATA from stage.
        version: Model version string. Auto-generated timestamp if None.
        is_active: Whether to mark models as active in catalog.
        write_mode: "overwrite" or "append" for MODEL_CATALOG.
        feature_spec: Feature views to use (e.g. "base/v1,weather/v1,rolling/v1").
    """
    train_version = version or get_train_version()
    train_run_id = f"training_{train_version}"

    if session is None:
        session = create_session(train_run_id)
        print(f"Connected: {session.get_current_account()}")
    else:
        session.sql(f"ALTER SESSION SET QUERY_TAG = '{train_run_id}'").collect()

    print("=" * 60)
    print(f"TRAINING ({mode.upper()})")
    print(f"   Version: {train_version}")
    print(f"   Hyperparams: {HYPERPARAMS}")
    print("=" * 60)

    if mode == "champion":
        # Champion: generate fresh dataset from Feature Store, train from DataFrame
        train_df, feature_metadata = prepare_data(session, feature_spec)
        execute_training(session, train_run_id, train_df=train_df)
    else:
        # Challenger: if --features is specified, regenerate data with different feature set
        # Otherwise reuse existing TRAIN_DATA (hyperparams-only experiment)
        if feature_spec:
            train_df, feature_metadata = prepare_data(session, feature_spec, table_prefix="CHALLENGER_")
        else:
            feature_metadata = {"feature_views": [], "feature_columns": [], "note": "reused existing TRAIN_DATA"}
            train_df = session.table("TRAIN_DATA")
        execute_training(session, train_run_id, train_df=train_df)

    collect_training_metrics(session, train_run_id, from_stage=False)
    update_model_catalog(session, train_version, train_run_id,
                         is_active=is_active, write_mode=write_mode,
                         feature_metadata=feature_metadata)

    print(f"RUN_ID={train_run_id}")
    return train_run_id


def parse_args():
    """Parse CLI arguments for training mode configuration."""
    parser = argparse.ArgumentParser(description="MMT Training Pipeline")
    parser.add_argument("--mode", choices=["champion", "challenger"], default="champion",
                        help="Training mode: champion (fresh data + overwrite) or challenger (reuse data + append)")
    parser.add_argument("--version", type=str, default=None,
                        help="Model version string. Defaults to timestamp for champion.")
    parser.add_argument("--hyperparams", type=str, default=None,
                        help="JSON string of XGBoost hyperparams (overrides defaults).")
    parser.add_argument("--features", type=str, default=None,
                        help="Feature views to use (e.g. 'base/v1,weather/v1,rolling/v1'). Default: all.")
    parser.add_argument("--register", action="store_true", default=False,
                        help="Register model to Model Registry after training.")
    parser.add_argument("--infer", action="store_true", default=False,
                        help="Run inference on TEST_DATA after registration (champion mode).")
    parser.add_argument("--run-experiment", action="store_true", default=False,
                        help="Run challenger inference + compare against champion in FORECAST_TELEMETRY.")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    # Set hyperparams globally before training (workers will pick this up)
    if args.hyperparams:
        HYPERPARAMS.update(json.loads(args.hyperparams))

    session = create_session()
    print(f"Connected: {session.get_current_account()}")

    # Determine catalog behavior based on mode
    is_active = (args.mode == "champion")
    write_mode = "overwrite" if args.mode == "champion" else "append"

    train_run_id = run_training(
        session,
        mode=args.mode,
        version=args.version,
        is_active=is_active,
        write_mode=write_mode,
        feature_spec=args.features,
    )

    if args.register:
        register_model(session)

    if args.infer:
        run_champion_inference(session)

    if args.run_experiment:
        # Use the same version that was used during training
        version = args.version or train_run_id.replace("training_", "")
        use_challenger_data = (args.mode == "challenger" and args.features is not None)
        run_challenger_inference(session, version, use_challenger_data=use_challenger_data)
        run_real_experiment(session, version)
