"""Experiment tracking: champion vs challenger model comparison and promotion.

Uses Snowflake ML ExperimentTracking API so experiments appear in Snowsight UI
(AI & ML > Experiments). All metrics and parameters are logged via the official API.
"""
from snowflake.snowpark import Session
from snowflake.ml.experiment import ExperimentTracking
import snowflake.snowpark.functions as F
from datetime import datetime
import numpy as np
import pandas as pd
from utils import create_session, get_feature_config, get_fully_qualified_name, get_experiment_config

feature_cfg = get_feature_config()
experiment_cfg = get_experiment_config()

GRAIN = feature_cfg["partition_col"]
TARGET = feature_cfg["target_col"]
TIME = feature_cfg["time_col"]

EXPERIMENT_NAME = "demand_forecast_experiment"


def _get_experiment_tracker(session: Session) -> ExperimentTracking:
    """Initialize ExperimentTracking and set the experiment."""
    exp = ExperimentTracking(session=session)
    exp.set_experiment(EXPERIMENT_NAME)
    return exp


def run_experiment(session: Session, champion_version: str, challenger_version: str,
                   champion_predictions: pd.DataFrame = None,
                   challenger_predictions: pd.DataFrame = None,
                   challenger_hyperparams: dict = None,
                   description: str = "") -> tuple:
    """
    Compare champion vs challenger predictions against actuals.
    Logs everything to Snowflake ExperimentTracking (visible in Snowsight UI).

    Returns (run_name, summary_dict).
    """
    telemetry_fqn = get_fully_qualified_name("FORECAST_TELEMETRY")
    exp = _get_experiment_tracker(session)

    run_name = f"exp_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"

    print(f"\n   Running experiment: {run_name}")
    print(f"   Champion: {champion_version}")
    print(f"   Challenger: {challenger_version}")

    # Get actuals from telemetry
    actuals = session.table(telemetry_fqn).select(GRAIN, TIME, "ACTUAL", "PREDICTED")
    actuals_pdf = actuals.to_pandas()

    if actuals_pdf.empty:
        print("   No telemetry data found. Run champion training with --infer first.")
        return run_name, {}

    # Champion = current predictions (from telemetry PREDICTED column)
    # Challenger = provided or simulated
    if challenger_predictions is None:
        np.random.seed(77)
        actuals_pdf["CHALLENGER_PRED"] = actuals_pdf["ACTUAL"] * (1 + np.random.normal(0, 0.08, len(actuals_pdf)))
        actuals_pdf["CHALLENGER_PRED"] = np.maximum(actuals_pdf["CHALLENGER_PRED"], 0)
    else:
        actuals_pdf = actuals_pdf.merge(challenger_predictions, on=[GRAIN, TIME], how="left")

    # Compute per-partition metrics
    partition_results = []
    for partition_id, group in actuals_pdf.groupby(GRAIN):
        actual = group["ACTUAL"].values
        champion_pred = group["PREDICTED"].values
        challenger_pred = group["CHALLENGER_PRED"].values

        champion_mape = float(np.mean(np.abs((actual - champion_pred) / np.maximum(actual, 1.0))))
        challenger_mape = float(np.mean(np.abs((actual - challenger_pred) / np.maximum(actual, 1.0))))
        champion_mae = float(np.mean(np.abs(actual - champion_pred)))
        challenger_mae = float(np.mean(np.abs(actual - challenger_pred)))
        winner = "challenger" if challenger_mape < champion_mape else "champion"

        partition_results.append({
            "partition_id": partition_id,
            "champion_mape": round(champion_mape, 4),
            "challenger_mape": round(challenger_mape, 4),
            "champion_mae": round(champion_mae, 2),
            "challenger_mae": round(challenger_mae, 2),
            "winner": winner,
        })

    results_df = pd.DataFrame(partition_results)

    # Compute aggregate summary
    challenger_wins = int((results_df["winner"] == "challenger").sum())
    champion_wins = int((results_df["winner"] == "champion").sum())
    total = len(results_df)
    avg_improvement = float(results_df["champion_mape"].mean() - results_df["challenger_mape"].mean())

    summary = {
        "partitions_improved": challenger_wins,
        "partitions_degraded": champion_wins,
        "total_partitions": total,
        "avg_mape_improvement": round(avg_improvement, 4),
        "champion_avg_mape": round(float(results_df["champion_mape"].mean()), 4),
        "challenger_avg_mape": round(float(results_df["challenger_mape"].mean()), 4),
        "champion_avg_mae": round(float(results_df["champion_mae"].mean()), 2),
        "challenger_avg_mae": round(float(results_df["challenger_mae"].mean()), 2),
        "overall_winner": "challenger" if challenger_wins > total // 2 else "champion",
    }

    # Log to Snowflake ExperimentTracking (appears in Snowsight Experiments UI)
    with exp.start_run(run_name):
        exp.log_params({
            "champion_version": champion_version,
            "challenger_version": challenger_version,
            "description": description or f"Challenger ({challenger_version}) vs Champion ({champion_version})",
            "total_partitions": str(total),
        })
        if challenger_hyperparams:
            for k, v in challenger_hyperparams.items():
                exp.log_param(f"challenger_{k}", v)

        exp.log_metrics({
            "champion_avg_mape": summary["champion_avg_mape"],
            "challenger_avg_mape": summary["challenger_avg_mape"],
            "avg_mape_improvement": summary["avg_mape_improvement"],
            "champion_avg_mae": summary["champion_avg_mae"],
            "challenger_avg_mae": summary["challenger_avg_mae"],
            "partitions_improved": float(challenger_wins),
            "partitions_degraded": float(champion_wins),
            "pct_partitions_improved": round(challenger_wins / total * 100, 1),
        })

    print(f"   Experiment complete!")
    print(f"   Challenger wins: {challenger_wins}/{total} ({challenger_wins/total*100:.1f}%)")
    print(f"   Champion avg MAPE: {summary['champion_avg_mape']:.2%}")
    print(f"   Challenger avg MAPE: {summary['challenger_avg_mape']:.2%}")
    print(f"   Improvement: {avg_improvement:.2%}")
    print(f"   Overall winner: {summary['overall_winner']}")

    return run_name, summary


def promote_challenger(session: Session, challenger_version: str, partitions: list = None):
    """
    Promote challenger model. Updates MODEL_CATALOG to set challenger as active.
    If partitions is None, promotes for all. Otherwise only for specified partitions.
    """
    catalog_fqn = get_fully_qualified_name("MODEL_CATALOG")

    if partitions:
        partition_list = ",".join([f"'{p}'" for p in partitions])
        condition = f"AND PARTITION_ID IN ({partition_list})"
    else:
        condition = ""

    session.sql(f"""
        UPDATE {catalog_fqn}
        SET MODEL_VERSION = '{challenger_version}', IS_ACTIVE = TRUE
        WHERE 1=1 {condition}
    """).collect()

    scope = f"{len(partitions)} partitions" if partitions else "all partitions"
    print(f"   Promoted challenger '{challenger_version}' for {scope}")


def run_demo_experiment(session: Session = None):
    """Demo entry point: runs a synthetic experiment to populate Snowsight UI."""
    if session is None:
        session = create_session("experiment_demo")
        print(f"Connected: {session.get_current_account()}")

    print("=" * 60)
    print("CHAMPION VS CHALLENGER EXPERIMENT")
    print("=" * 60)

    run_name, summary = run_experiment(
        session,
        champion_version="v20260301_baseline",
        challenger_version="v20260315_weather_features",
        description="Testing impact of adding WEATHER_TEMP as feature"
    )

    print(f"\n{'=' * 60}")
    print("EXPERIMENT COMPLETE")
    print(f"{'=' * 60}")

    return run_name, summary


if __name__ == "__main__":
    session = create_session()
    session.use_role("SYSADMIN")
    print(f"Connected: {session.get_current_account()}")
    run_demo_experiment(session)
