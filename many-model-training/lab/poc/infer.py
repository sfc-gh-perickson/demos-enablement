"""Inference pipeline: score TEST_DATA via the registered partitioned model."""
from snowflake.snowpark import Session
import snowflake.snowpark.functions as F

from snowflake.ml.registry import Registry

from datetime import datetime
from utils import (
    get_feature_config, create_session, get_fully_qualified_name
)

feature_cfg = get_feature_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]
EXCLUDE_COLS = [GRAIN, TARGET, TIME]


def get_model_version(session: Session, model_name: str = "MMT_DEMAND_MODEL"):
    """Return the default ModelVersion for the registered partitioned model."""
    reg = Registry(
        session=session,
        database_name=session.get_current_database(),
        schema_name=session.get_current_schema(),
    )
    return reg.get_model(model_name).default


def score_test_data(session: Session, model_name: str = "MMT_DEMAND_MODEL"):
    """Run partitioned inference over TEST_DATA and write PREDICTIONS table."""
    infer_data = session.table("TEST_DATA")

    # Model signature excludes the target column; keep features + grain + time.
    # Cast numeric features to DOUBLE to match the FLOAT model signature.
    from snowflake.snowpark.types import DoubleType
    input_cols = [c for c in infer_data.columns if c != TARGET]
    infer_input = infer_data.select(input_cols)
    infer_input = infer_input.select([
        F.col(c).cast(DoubleType()).alias(c) if c not in (GRAIN, TIME) else F.col(c)
        for c in infer_input.columns
    ])

    mv = get_model_version(session, model_name)
    print(f"   Using model: {mv.model_name} version {mv.version_name}")

    result = mv.run(infer_input, function_name="predict", partition_column=GRAIN)

    predictions = result.select(
        F.col(f"OUTPUT_{GRAIN}").alias(GRAIN),
        F.col(f"OUTPUT_{TIME}").alias(TIME),
        F.col(f"PRED_{TARGET}").alias("PREDICTION"),
    )

    # Attach actuals for downstream evaluation.
    actuals = session.table("TEST_DATA").select(GRAIN, TIME, TARGET)
    final = predictions.join(actuals, on=[GRAIN, TIME], how="left")

    final.write.mode("overwrite").save_as_table("PREDICTIONS")
    return final.count()


def show_sample_predictions(session: Session):
    """Print sample rows from PREDICTIONS table."""
    print("\n   Sample Predictions:")
    predictions_fqn = get_fully_qualified_name("PREDICTIONS")
    session.table(predictions_fqn).show(5)


def run_inference(session: Session = None, model_name: str = "MMT_DEMAND_MODEL") -> str:
    """Entry point: score TEST_DATA via the registered model. Returns inference_run_id."""
    inference_run_id = f"inference_{datetime.utcnow().strftime('%Y%m%d_%H%M')}"

    if session is None:
        session = create_session(inference_run_id)
        print(f"Connected: {session.get_current_account()}")
    else:
        session.sql(f"ALTER SESSION SET QUERY_TAG = '{inference_run_id}'").collect()

    print(f"\n   Starting Many Model Inference")
    print(f"   Inference run ID: {inference_run_id}")

    count = score_test_data(session, model_name)
    print(f"   Predictions written: {count:,}")

    show_sample_predictions(session)

    return inference_run_id


if __name__ == "__main__":
    session = create_session()
    print(f"Connected: {session.get_current_account()}")
    run_id = run_inference(session)
    print(f"RUN_ID={run_id}")
