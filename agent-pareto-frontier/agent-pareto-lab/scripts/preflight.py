"""Preflight before starting evals: catch config mistakes that otherwise surface only after every run has scored.

Usage: python preflight.py lab.yaml
Checks:
  - the dataset object and its source table (`dataset_table` in lab.yaml) are readable with the lab role
  - ground-truth keys the selected metrics read are present:
      answer_correctness            -> ground_truth_output
      tool_selection_accuracy /
      tool_execution_accuracy       -> ground_truth_invocations
    custom judges read the whole VARIANT via {{ground_truth}}; list the keys a judge needs in its
    `ground_truth_keys` in lab.yaml and they are checked too
  - ground_truth_output placeholders (X, Y, $X ...) that make answer_correctness meaningless
  - every variant warehouse and eval_warehouse exists
Exit 1 on a blocking problem, 0 otherwise (warnings are printed).
"""
import sys

from common import connect, load_lab

KEYS = {"answer_correctness": "ground_truth_output",
        "tool_selection_accuracy": "ground_truth_invocations",
        "tool_execution_accuracy": "ground_truth_invocations"}


def metric_name(m):
    return m if isinstance(m, str) else m["name"]


def main():
    lab = load_lab(sys.argv[1])
    conn = connect(lab)
    cur = conn.cursor()
    errors, warns = [], []

    cur.execute(f"SHOW DATASETS LIKE '{lab['dataset'].split('.')[-1]}' IN SCHEMA {'.'.join(lab['dataset'].split('.')[:2])}")
    if not cur.fetchall():
        errors.append(f"dataset {lab['dataset']} not found or not visible to the lab role")

    table = lab.get("dataset_table")
    if not table:
        warns.append("dataset_table not set: ground-truth keys not checked (set it to the table behind the dataset)")
    else:
        gt = lab.get("ground_truth_column", "GROUND_TRUTH")
        cur.execute(f"SELECT COUNT(*), {', '.join(f'COUNT_IF({gt}:{k} IS NOT NULL)' for k in sorted(set(KEYS.values())))} "
                    f"FROM {table}")
        row = cur.fetchone()
        total, have = row[0], dict(zip(sorted(set(KEYS.values())), row[1:]))
        cur.execute(f"SELECT DISTINCT f.key FROM {table}, LATERAL FLATTEN(input => {gt}) f")
        present = sorted(r[0] for r in cur.fetchall())
        print(f"dataset table {table}: {total} rows, ground-truth keys {present}")
        for m in lab["metrics"]:
            name = metric_name(m)
            key = KEYS.get(name)
            if key and have[key] == 0:
                errors.append(f"metric {name} reads {gt}:{key}, present in 0/{total} rows "
                              f"(keys present: {present}). Rebuild the ground truth or drop the metric.")
            elif key and have[key] < total:
                warns.append(f"metric {name}: {gt}:{key} present in only {have[key]}/{total} rows")
            for k in (m.get("ground_truth_keys") or []) if isinstance(m, dict) else []:
                if k not in present:
                    errors.append(f"judge {name} needs ground-truth key '{k}', not in dataset (keys: {present})")
        if have["ground_truth_output"]:
            cur.execute(f"SELECT COUNT_IF(REGEXP_LIKE({gt}:ground_truth_output::string, "
                        r"'.*(\\$?\\b[XYZW]\\b).*')) FROM " + table)
            ph = cur.fetchone()[0]
            if ph:
                warns.append(f"{ph}/{total} ground_truth_output values contain placeholders (X/Y/Z/W): "
                             "answer_correctness on those rows is noise; use literal values")

    for wh in sorted({v["warehouse"] for v in lab["variants"] if v.get("warehouse")} | {lab["eval_warehouse"]}):
        cur.execute(f"SHOW WAREHOUSES LIKE '{wh}'")
        if not cur.fetchall():
            errors.append(f"warehouse {wh} does not exist")

    for w in warns:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print("preflight", "FAILED" if errors else "ok")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
