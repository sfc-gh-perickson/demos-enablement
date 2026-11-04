"""Shared helpers: lab.yaml loading, spec merging, eval YAML rendering, Snowflake connection."""
import copy
import json
import os
import re

import jinja2
import yaml

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_env = jinja2.Environment(loader=jinja2.FileSystemLoader(SKILL_DIR), keep_trailing_newline=True,
                          undefined=jinja2.StrictUndefined)
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*$")


def load_lab(path):
    """Load lab.yaml and resolve file paths relative to its directory."""
    path = os.path.abspath(path)
    with open(path) as f:
        lab = yaml.safe_load(f)
    lab["_dir"] = os.path.dirname(path)
    db, schema, name = lab["agent"].split(".")
    lab["_db"], lab["_schema"], lab["_name"] = db, schema, name
    for part in (db, schema, name, lab["run_prefix"]):
        if not IDENT.match(part):
            raise ValueError(f"not a plain identifier: {part!r}")
    prefix = lab["run_prefix"]
    for v in lab["variants"]:
        # `name` is the short variant name; the agent alias is <run_prefix>_<name> so it stays unique across
        # rounds. A legacy explicit `alias` is still accepted; its short name drops a leading "<run_prefix>_".
        if "alias" not in v:
            v["alias"] = f"{prefix}_{v['name']}"
        v.setdefault("name", v["alias"][len(prefix) + 1:] if v["alias"].lower().startswith(prefix.lower() + "_")
                     else v["alias"])
        for key in ("alias", "name"):
            if not IDENT.match(v[key]):
                raise ValueError(f"variant {key} must be a plain identifier: {v[key]!r}")
    lab.setdefault("repeats", 1)
    lab.setdefault("correct_threshold", 0.7)
    lab.setdefault("out_dir", "pareto_out")
    lab["_out"] = os.path.join(lab["_dir"], lab["out_dir"], lab["run_prefix"])
    return lab


def rel(lab, p):
    return p if os.path.isabs(p) else os.path.join(lab["_dir"], p)


def merge_patch(target, patch):
    """RFC 7386 JSON merge patch: dicts merge, null deletes, everything else (incl. lists) replaces."""
    if not isinstance(patch, dict):
        return copy.deepcopy(patch)
    out = copy.deepcopy(target) if isinstance(target, dict) else {}
    for k, v in patch.items():
        if v is None:
            out.pop(k, None)
        else:
            out[k] = merge_patch(out.get(k), v)
    return out


def variant_spec(lab, variant):
    """Base spec (or the variant's own spec file) + overrides + per-variant tool warehouse."""
    with open(rel(lab, variant.get("spec", lab["base_spec"]))) as f:
        spec = json.load(f)
    spec = merge_patch(spec, variant.get("overrides") or {})
    wh = variant.get("warehouse")
    if wh:
        for res in (spec.get("tool_resources") or {}).values():
            env = res.get("execution_environment")
            if isinstance(env, dict) and env.get("type") == "warehouse":
                env["warehouse"] = wh
    return spec


def run_name(lab, variant, k, repeats=None):
    """<run_prefix>_<name>, plus _r<k> only when the variant is run more than once."""
    base = f"{lab['run_prefix']}_{variant['name']}"
    return base if (repeats or lab["repeats"]) == 1 else f"{base}_r{k}"


def render_eval_yaml(lab, variant, version_name):
    metrics = []
    for m in lab["metrics"]:
        if isinstance(m, str):
            metrics.append({"builtin": m})
        elif "prompt_file" in m:
            with open(rel(lab, m["prompt_file"])) as f:
                prompt = f.read().rstrip("\n")
            metrics.append({**m, "prompt": prompt})
        else:
            metrics.append(m)
    return _env.get_template("templates/eval.yaml.j2").render(
        lab=lab, variant=variant, version_name=version_name, metrics=metrics)


def render_sql(template, **kw):
    return _env.get_template(template).render(**kw)


def connect(lab):
    import snowflake.connector
    conn = snowflake.connector.connect(connection_name=lab["connection"], client_session_keep_alive=True)
    cur = conn.cursor()
    if lab.get("role"):
        cur.execute(f"USE ROLE {lab['role']}")
    cur.execute(f"USE SCHEMA {lab['_db']}.{lab['_schema']}")
    try:
        cur.execute(f"USE WAREHOUSE {lab['eval_warehouse']}")
    except Exception as e:  # preflight reports a missing warehouse; other scripts fail on first query
        print(f"note: eval_warehouse {lab['eval_warehouse']} not usable: {str(e).splitlines()[-1][:120]}")
    return conn


def alias_versions(cur, lab, specs=None):
    """{ALIAS_UPPER: VERSION$n} for committed versions; fills specs {ALIAS_UPPER: spec dict} if given."""
    cur.execute(f"SHOW VERSIONS IN AGENT {lab['agent']}")
    cols = [c[0].lower() for c in cur.description]
    out = {}
    for row in cur.fetchall():
        r = dict(zip(cols, row))
        for a in str(r.get("aliases") or r.get("alias") or "").strip("[]").replace('"', "").split(","):
            if a.strip():
                out[a.strip().upper()] = r["name"]
                if specs is not None and r.get("agent_spec"):
                    specs[a.strip().upper()] = json.loads(r["agent_spec"])
    return out
