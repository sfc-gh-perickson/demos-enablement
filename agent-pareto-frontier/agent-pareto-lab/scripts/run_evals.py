"""Upload eval configs, start <repeats> runs per variant, and poll every run to a terminal state.

Usage: python run_evals.py lab.yaml [--only name1,name2] [--repeats N] [--poll-only] [--dry-run]
Requires `generate.py --apply` first (eval YAMLs must carry real VERSION$n names).
Run names are <run_prefix>_<name> (with _r<k> only when repeats > 1); an existing run name is never restarted.
Configs are uploaded once per run_prefix and never overwritten: change config => new run_prefix.
"""
import json
import os
import sys
import time

from common import connect, load_lab, run_name

TERMINAL = {"COMPLETED", "FAILED", "PARTIALLY_COMPLETED", "CANCELLED"}


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def status(cur, run, cfg):
    try:
        cur.execute("CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', %s), %s)", (run, cfg))
    except Exception as e:
        return None, str(e).splitlines()[0]
    cols = [c[0].upper() for c in cur.description]
    row = dict(zip(cols, cur.fetchall()[0]))
    st = str(row.get("STATUS", "UNKNOWN"))
    return st.upper(), json.dumps(row, default=str)[:300]


def main():
    lab = load_lab(sys.argv[1])
    only = set((arg("--only") or "").split(",")) - {""}
    repeats = int(arg("--repeats", lab["repeats"]))
    variants = [v for v in lab["variants"] if not only or v["alias"] in only or v["name"] in only]
    stage = f"@{lab['config_stage']}/{lab['run_prefix']}"
    conn = connect(lab)
    cur = conn.cursor()

    runs = []  # (run_name, config_path)
    for v in variants:
        local = os.path.join(lab["_out"], "evals", f"{v['alias']}.yaml")
        with open(local) as f:
            if "<pending>" in f.read():
                sys.exit(f"{local} has no version yet: run generate.py --apply first")
        cfg = f"{stage}/{v['alias']}.yaml"
        runs += [(run_name(lab, v, k, repeats), cfg) for k in range(1, repeats + 1)]
        if "--poll-only" in sys.argv or "--dry-run" in sys.argv:
            continue
        cur.execute(f"CREATE STAGE IF NOT EXISTS {lab['config_stage']} DIRECTORY = (ENABLE = TRUE) ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')")
        cur.execute(f"LIST {stage}/{v['alias']}.yaml")
        if cur.fetchall():
            print(f"config exists, not overwritten: {cfg}")
        else:
            cur.execute(f"PUT 'file://{local}' {stage}/ AUTO_COMPRESS = FALSE OVERWRITE = FALSE")
            print(f"uploaded {cfg}")

    if "--dry-run" in sys.argv:
        print("\n".join(f"{r}  {c}" for r, c in runs))
        return

    if "--poll-only" not in sys.argv:
        for r, cfg in runs:
            st, _ = status(cur, r, cfg)
            if st:
                print(f"exists {r}: {st}")
                continue
            cur.execute("CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', %s), %s)", (r, cfg))
            print(f"started {r}")

    for i in range(int(arg("--max-polls", 120))):
        states = {r: status(cur, r, cfg) for r, cfg in runs}
        done = [r for r, (st, _) in states.items() if st in TERMINAL]
        print(time.strftime("%H:%M:%S"), f"{len(done)}/{len(runs)} terminal",
              {r: st for r, (st, _) in states.items() if st not in TERMINAL}, flush=True)
        if len(done) == len(runs):
            break
        time.sleep(60)
    bad = {r: d for r, (st, d) in states.items() if st != "COMPLETED"}
    if bad:
        print("NOT COMPLETED (report these, do not silently drop):")
        for r, d in bad.items():
            print(f"  {r}: {d}")
    out = os.path.join(lab["_out"], "runs.json")
    with open(out, "w") as f:
        json.dump({r: st for r, (st, _) in states.items()}, f, indent=1)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
