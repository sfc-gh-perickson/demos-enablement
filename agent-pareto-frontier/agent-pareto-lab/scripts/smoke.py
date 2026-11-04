"""Smoke-test one question against every variant's committed version, in SQL (no REST).

Usage: python smoke.py lab.yaml ["question"]   (default question: first INPUT_QUERY of the dataset table)
Runs SNOWFLAKE.CORTEX.DATA_AGENT_RUN('<db.schema.agent>!<ALIAS>', <request>) per variant.
The alias after `!` must be UPPER case: a lower-case alias returns an error object instead of raising.
"""
import json
import sys
import time

from common import alias_versions, connect, load_lab


def main():
    lab = load_lab(sys.argv[1])
    conn = connect(lab)
    cur = conn.cursor()
    question = sys.argv[2] if len(sys.argv) > 2 else lab.get("smoke_question")
    if not question:
        sys.exit("pass a question (or set smoke_question in lab.yaml)")
    versions = alias_versions(cur, lab)
    body = json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]})
    bad = 0
    for v in lab["variants"]:
        alias = v["alias"].upper()
        if alias not in versions:
            print(f"{v['name']:<20} MISSING alias {alias}: run generate.py --apply first")
            bad += 1
            continue
        t = time.time()
        try:
            cur.execute("SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(%s, %s)", (f"{lab['agent']}!{alias}", body))
            r = json.loads(cur.fetchone()[0])
        except Exception as e:
            print(f"{v['name']:<20} ERROR {str(e).splitlines()[0][:160]}")
            bad += 1
            continue
        if "content" not in r:  # error object, e.g. {"code","message","error_code"}
            print(f"{v['name']:<20} ERROR {json.dumps(r)[:200]}")
            bad += 1
            continue
        tools = [c.get("tool_use", {}).get("name") for c in r["content"] if c.get("type") == "tool_use"]
        text = [c.get("text", "") for c in r["content"] if c.get("type") == "text"]
        print(f"{v['name']:<20} {versions[alias]:<11} {time.time() - t:6.1f}s tools={tools} :: "
              f"{(text[-1] if text else '').strip()[:100]!r}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
