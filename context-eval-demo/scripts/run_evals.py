#!/usr/bin/env python3
"""Run the 20-question eval set against every tagged version of REVENUE_ASSISTANT.

    python3 scripts/run_evals.py -c <connection>                       # all versions, new tag
    python3 scripts/run_evals.py -c <connection> --versions V1_GOVERNED_SV,V4_INSTRUCTIONS --no-wait

Each run is recorded in EVALS.EVAL_RUNS; the app's Results tab reads the most recent tag.
Runs execute in parallel in Snowflake and usually finish in 10-25 minutes.
"""
import argparse
import datetime
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sf import AGENT, common_args, ctx_from  # noqa: E402

CONFIG = """{dataset}evaluation:
  agent_params:
    agent_name: "{db}.{agent}"
    agent_type: "CORTEX AGENT"
    agent_version: "{alias}"
  run_params:
    label: "context-eval {alias}"
    description: "Eval tag {tag}"
  source_metadata:
    type: "dataset"
    dataset_name: "{ds}"
metrics:
  - name: "answer_correctness"
  - name: "logical_consistency"
"""
DATASET = """dataset:
  dataset_type: "CORTEX AGENT"
  table_name: "{db}.EVALS.EVAL_SET"
  dataset_name: "{ds}"
  column_mapping:
    query_text: "INPUT_QUERY"
    ground_truth: "GROUND_TRUTH"
"""


def main():
    p = common_args(argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter))
    p.add_argument("--versions", default=None, help="comma-separated aliases (default: every aliased version)")
    p.add_argument("--tag", default=None, help="run tag (default: e<timestamp>)")
    p.add_argument("--no-wait", action="store_true", help="start the runs and exit")
    a = p.parse_args()
    c = ctx_from(a)
    c.schema = "EVALS"
    fqn = f"{c.db}.{AGENT}"
    aliases = [r["alias"] for r in c.q(f"SHOW VERSIONS IN AGENT {fqn}") if r.get("alias")]
    aliases = sorted(a.versions.upper().split(",") if a.versions else aliases)
    tag = a.tag or "e" + datetime.datetime.utcnow().strftime("%Y%m%d%H%M")
    ds = f"DS_{tag.upper()}"
    c.q(f"CREATE TABLE IF NOT EXISTS {c.db}.EVALS.EVAL_RUNS (TAG STRING, VERSION_ALIAS STRING, RUN_NAME STRING, STARTED_AT TIMESTAMP_LTZ)")
    c.q(f"CREATE STAGE IF NOT EXISTS {c.db}.EVALS.CONFIGS")

    runs = {}
    for i, alias in enumerate(aliases):
        cfg_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "evals", "generated", tag)
        os.makedirs(cfg_dir, exist_ok=True)
        path = os.path.join(cfg_dir, f"{alias}.yaml")
        # Only the first config carries the dataset block: START creates the dataset once, the rest reuse it.
        dataset = DATASET.format(db=c.db, ds=ds) if i == 0 else ""
        with open(path, "w") as f:
            f.write(CONFIG.format(dataset=dataset, db=c.db, agent=AGENT, alias=alias, tag=tag, ds=ds))
        c.q(f"PUT 'file://{os.path.abspath(path)}' '@{c.db}.EVALS.CONFIGS/{tag}/' AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
        run = f"{tag}_{alias}"
        cfg = f"@{c.db}.EVALS.CONFIGS/{tag}/{alias}.yaml"
        c.q(f"CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', '{run}'), '{cfg}')")
        c.q(f"INSERT INTO {c.db}.EVALS.EVAL_RUNS VALUES ('{tag}', '{alias}', '{run}', CURRENT_TIMESTAMP())")
        runs[alias] = (run, cfg)
        print(f"started {run}")
        if i == 0:
            time.sleep(20)  # let the first run materialize the shared dataset

    if a.no_wait:
        print(f"\nTag {tag}. Check progress in the app or with python3 scripts/run_evals.py --help.")
        return
    pending = dict(runs)
    while pending:
        time.sleep(60)
        for alias, (run, cfg) in list(pending.items()):
            s = str(c.q(f"CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', '{run}'), '{cfg}')", check=False)).upper()
            if "COMPLETED" in s or "FAILED" in s or "CANCELLED" in s:
                print(f"{run}: {'COMPLETED' if 'COMPLETED' in s else 'FAILED'}")
                pending.pop(alias)
        if pending:
            print(f"  waiting on {', '.join(pending)}")
    print(f"\nDone. Tag {tag}; the app's Results tab now shows these runs.")


if __name__ == "__main__":
    main()
