#!/usr/bin/env python3
"""Remove the context-eval demo from an account.

    python3 scripts/teardown.py -c <connection> --database CONTEXT_EVAL_DEMO            # dry run: prints what it would drop
    python3 scripts/teardown.py -c <connection> --database CONTEXT_EVAL_DEMO --yes      # do it

Order: eval runs, then the database (agent, semantic views, data, app, Sense context schema).
The Business Ontology node 'Revenue Demo.Bookings' is account-wide and shared by every install in
the account, so it is kept unless you pass --ontology.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sf import common_args, ctx_from  # noqa: E402
from deploy import ONTOLOGY_NODES  # noqa: E402


def main():
    p = common_args(argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter))
    p.add_argument("--yes", action="store_true", help="actually drop (default is a dry run)")
    p.add_argument("--ontology", action="store_true", help="also delete the Revenue Demo ontology domain and its nodes")
    a = p.parse_args()
    c = ctx_from(a)
    c.schema = "EVALS"
    runs = c.q(f"SELECT TAG, RUN_NAME, VERSION_ALIAS FROM {c.db}.EVALS.EVAL_RUNS", check=False)
    runs = runs if isinstance(runs, list) else []
    print(f"Database {c.db}: {len(runs)} eval runs, then DROP DATABASE.")
    if a.ontology:
        print("Business Ontology: delete nodes in domain 'Revenue Demo'.")
    if not a.yes:
        print("Dry run. Re-run with --yes to drop.")
        return
    for r in runs:
        cfg = f"@{c.db}.EVALS.CONFIGS/{r['TAG']}/{r['VERSION_ALIAS']}.yaml"
        c.q(f"CALL EXECUTE_AI_EVALUATION('DELETE', OBJECT_CONSTRUCT('run_name', '{r['RUN_NAME']}'), '{cfg}')", check=False)
        print("deleted run", r["RUN_NAME"])
    c.schema = None
    c.q(f"DROP DATABASE IF EXISTS {c.db}")
    print("dropped", c.db)
    if a.ontology:
        for n in ONTOLOGY_NODES:
            t = c.scalar(f"SELECT SYSTEM$GET_GLOSSARY_TERM('Revenue Demo.{n['name']}')", check=False)
            if not isinstance(t, dict) and t and not json.loads(t).get("error"):
                c.scalar(f"SELECT SYSTEM$DELETE_GLOSSARY_TERM('{json.loads(t)['termId']}')", check=False)
        c.scalar("SELECT SYSTEM$DELETE_GLOSSARY_DOMAIN('Revenue Demo')", check=False)
        print("deleted ontology nodes and domain")


if __name__ == "__main__":
    main()
