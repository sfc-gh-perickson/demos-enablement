"""Render variant specs, version SQL and eval YAMLs from lab.yaml; optionally apply them.

Usage:
  python generate.py lab.yaml                 # offline render to <out_dir>/<run_prefix>/
  python generate.py lab.yaml --apply         # create missing versions + aliases, then re-render YAMLs with real versions
  python generate.py lab.yaml --diff          # print each variant's spec diff against base_spec
Never replaces a committed version: an alias that already exists is skipped (a changed spec needs a new alias).
"""
import difflib
import json
import os
import re
import sys

from common import alias_versions, connect, load_lab, rel, render_eval_yaml, variant_spec


def spec_sql(spec):
    body = json.dumps(spec, ensure_ascii=True)
    if "$$" in body:
        raise ValueError("spec contains '$$'; cannot dollar-quote it")
    return f"$${body}$$"


def version_statements(lab, variant, spec, agent_exists):
    a = lab["agent"]
    comment = (variant.get("label") or variant["alias"]).replace("'", "''")
    if not agent_exists:
        return [f"CREATE AGENT IF NOT EXISTS {a} COMMENT = 'agent-pareto-lab' FROM SPECIFICATION {spec_sql(spec)}"]
    return [f"ALTER AGENT {a} ADD LIVE VERSION FROM LAST",
            f"ALTER AGENT {a} MODIFY LIVE VERSION SET SPECIFICATION = {spec_sql(spec)}",
            f"ALTER AGENT {a} COMMIT COMMENT = '{comment}'"]


def newest_version(cur, lab):
    cur.execute(f"SHOW VERSIONS IN AGENT {lab['agent']}")
    cols = [c[0].lower() for c in cur.description]
    names = [dict(zip(cols, r))["name"] for r in cur.fetchall()]
    return max(names, key=lambda n: int(re.sub(r"\D", "", n) or 0))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def render_all(lab, versions):
    for v in lab["variants"]:
        write(os.path.join(lab["_out"], "specs", f"{v['alias']}.json"), json.dumps(variant_spec(lab, v), indent=2) + "\n")
        name = versions.get(v["alias"].upper(), "<pending>")
        write(os.path.join(lab["_out"], "evals", f"{v['alias']}.yaml"), render_eval_yaml(lab, v, name))


def main():
    lab = load_lab(sys.argv[1])
    if "--diff" in sys.argv:
        with open(rel(lab, lab["base_spec"])) as f:
            base = json.dumps(json.load(f), indent=1, sort_keys=True).splitlines()
        for v in lab["variants"]:
            new = json.dumps(variant_spec(lab, v), indent=1, sort_keys=True).splitlines()
            print(f"=== {v['alias']}")
            print("\n".join(l[:200] for l in difflib.unified_diff(base, new, "base", v["alias"], n=0, lineterm="")) or "(same as base)")
        return

    if "--apply" not in sys.argv:
        # offline: predict VERSION$n assuming none of the aliases exist yet and the agent has N versions
        n0 = int(sys.argv[sys.argv.index("--assume-existing") + 1]) if "--assume-existing" in sys.argv else 0
        if "--assume-existing" not in sys.argv:
            print("note: preview assumes a NEW agent (CREATE AGENT, first variant -> VERSION$1). For an existing agent "
                  "pass --assume-existing <number of committed versions> (see SHOW VERSIONS IN AGENT).")
        versions = {v["alias"].upper(): f"VERSION${n0 + i + 1}" for i, v in enumerate(lab["variants"])}
        render_all(lab, versions)
        sql = []
        for i, v in enumerate(lab["variants"]):
            sql.append(f"-- {v['alias']} -> {versions[v['alias'].upper()]} (predicted)")
            sql += [s + ";" for s in version_statements(lab, v, variant_spec(lab, v), agent_exists=(n0 + i) > 0)]
            sql.append(f"ALTER AGENT {lab['agent']} MODIFY VERSION {versions[v['alias'].upper()]} SET ALIAS = {v['alias']};")
        write(os.path.join(lab["_out"], "versions.sql"), "\n".join(sql) + "\n")
        print(f"rendered {len(lab['variants'])} variants to {lab['_out']}")
        return

    conn = connect(lab)
    cur = conn.cursor()
    cur.execute(f"SHOW AGENTS LIKE '{lab['_name']}' IN SCHEMA {lab['_db']}.{lab['_schema']}")
    agent_exists = bool(cur.fetchall())
    specs = {}
    versions = alias_versions(cur, lab, specs) if agent_exists else {}
    for v in lab["variants"]:
        if v["alias"].upper() in versions:
            same = specs.get(v["alias"].upper()) == variant_spec(lab, v)
            print(f"skip {v['alias']}: already {versions[v['alias'].upper()]}" +
                  ("" if same else "  WARNING: committed spec differs from lab.yaml; use a new alias for the change"))
            continue
        for stmt in version_statements(lab, v, variant_spec(lab, v), agent_exists):
            try:
                cur.execute(stmt)
            except Exception as e:  # a live version may already exist (e.g. right after CREATE AGENT)
                if "ADD LIVE VERSION" in stmt:
                    print(f"  note: {str(e).splitlines()[0][:160]}")
                    continue
                raise
        agent_exists = True
        name = newest_version(cur, lab)
        cur.execute(f"ALTER AGENT {lab['agent']} MODIFY VERSION {name} SET ALIAS = {v['alias']}")
        versions[v["alias"].upper()] = name
        print(f"created {v['alias']} -> {name}")
    render_all(lab, versions)
    print(json.dumps(versions, indent=1))


if __name__ == "__main__":
    main()
