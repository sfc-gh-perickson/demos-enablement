#!/usr/bin/env python3
"""
Check Cortex Agent evaluation results and fail CI if below thresholds.

Usage:
    python scripts/check_eval_results.py --database AGENT_CICD_DEV
"""

import argparse
import json
import os
import sys
import time

try:
    import snowflake.connector
except ImportError:
    print("ERROR: snowflake-connector-python not installed")
    print("Install with: pip install snowflake-connector-python")
    sys.exit(1)


# Score thresholds - CI fails if any metric falls below these
THRESHOLDS = {
    "tool_selection_accuracy": 0.8,
    "answer_correctness": 0.6,
    "logical_consistency": 0.7,
}

MAX_WAIT_SECONDS = 300
POLL_INTERVAL_SECONDS = 15


def get_connection(database: str):
    """Create Snowflake connection from environment variables."""
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        password=os.environ.get("SNOWFLAKE_PASSWORD", ""),
        authenticator=os.environ.get("SNOWFLAKE_AUTHENTICATOR", "snowflake"),
        role=os.environ.get("SNOWFLAKE_ROLE", "SYSADMIN"),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH"),
        database=database,
    )


def run_evaluation(conn, database: str) -> str:
    """Start the evaluation and return the run ID."""
    cursor = conn.cursor()
    cursor.execute(f"""
        SELECT CORTEX.RUN_EVALUATION(
            MODEL => '{database}.SEMANTIC.RETAIL_ASSISTANT',
            DATASET => '{database}.EVALUATION.AGENT_EVAL_DATASET',
            METRICS => ['tool_selection_accuracy', 'answer_correctness', 'logical_consistency']
        ) AS eval_run_id
    """)
    result = cursor.fetchone()
    return result[0]


def poll_evaluation(conn, eval_run_id: str) -> dict:
    """Poll evaluation status until complete or timeout."""
    cursor = conn.cursor()
    elapsed = 0

    while elapsed < MAX_WAIT_SECONDS:
        cursor.execute(f"""
            SELECT status, results
            FROM TABLE(CORTEX.GET_EVALUATION_STATUS('{eval_run_id}'))
        """)
        row = cursor.fetchone()

        if row and row[0] == "COMPLETED":
            return json.loads(row[1]) if isinstance(row[1], str) else row[1]
        elif row and row[0] == "FAILED":
            print(f"ERROR: Evaluation failed: {row[1]}")
            sys.exit(1)

        print(f"  Evaluation in progress... ({elapsed}s elapsed)")
        time.sleep(POLL_INTERVAL_SECONDS)
        elapsed += POLL_INTERVAL_SECONDS

    print(f"ERROR: Evaluation timed out after {MAX_WAIT_SECONDS}s")
    sys.exit(1)


def check_thresholds(results: dict) -> bool:
    """Check if all metrics meet thresholds. Returns True if passed."""
    passed = True
    print("\n" + "=" * 60)
    print("EVALUATION RESULTS")
    print("=" * 60)

    for metric, threshold in THRESHOLDS.items():
        score = results.get(metric, 0)
        status = "PASS" if score >= threshold else "FAIL"
        if score < threshold:
            passed = False
        print(f"  {metric:30s} {score:.3f}  (threshold: {threshold:.2f})  [{status}]")

    print("=" * 60)
    print(f"Overall: {'PASSED' if passed else 'FAILED'}")
    print("=" * 60)
    return passed


def main():
    parser = argparse.ArgumentParser(description="Check Cortex Agent evaluation results")
    parser.add_argument("--database", required=True, help="Target database (AGENT_CICD_DEV or AGENT_CICD_PROD)")
    parser.add_argument("--skip-run", action="store_true", help="Skip running eval, just check latest results")
    args = parser.parse_args()

    print(f"Connecting to {args.database}...")
    conn = get_connection(args.database)

    print("Starting agent evaluation...")
    eval_run_id = run_evaluation(conn, args.database)
    print(f"Evaluation started: {eval_run_id}")

    print("Waiting for results...")
    results = poll_evaluation(conn, eval_run_id)

    passed = check_thresholds(results)

    conn.close()
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
