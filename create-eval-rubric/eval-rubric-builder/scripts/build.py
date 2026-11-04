"""eval-rubric-builder build steps.

  build.py coverage <dir>          question coverage matrix (incl. persona x category)
  build.py draft-personas <dir>    maker checklist: evidence to gather + persona card gaps
  build.py suggest-metrics <dir>   draft business / persona custom_metrics from intake (for review)
  build.py export   <dir>          candidate_dataset.csv, rules.csv, calibration_template.csv, sheet_payload.json
  build.py judges   <dir>          render judges/<metric>@v1.md from templates + intake
  build.py studio   <dir> <metric> render calibration SQL + create_udf command for a Tier B judge
  build.py sql      <dir>          dataset.sql + eval_config.yaml from the latest dataset_v<N>.csv
  build.py spec     <dir>          customer-facing spec.md
"""
from __future__ import annotations

import argparse
import json
import shlex
import sys
from collections import Counter, defaultdict
from pathlib import Path

from jinja2 import Template
import yaml

sys.path.insert(0, str(Path(__file__).parent))
from common import (BUILTINS, PERSONA_FIELDS, TEMPLATES, bullets, custom_metrics, dumps, frozen_judge,  # noqa: E402
                    ground_truth, judge_template, latest_dataset, load_intake, metric_tiers, read_csv, render_custom,
                    render_judge, scoring, sql_str, strip_header, taxonomy, write_csv)

Q_FIELDS = (TEMPLATES / "questions_header.csv").read_text().strip().split(",")


def coverage(d: Path) -> None:
    intake, rows = load_intake(d), read_csv(d / "questions.csv")
    print(f"{len(rows)} questions")
    for col in ("persona", "intent", "process", "date_type", "risk"):
        print(f"  {col:10s}", dict(Counter(r.get(col) or "-" for r in rows)))
    gaps = []
    personas = {p["id"] for p in intake.get("personas", [])}
    missing = personas - {r.get("persona") for r in rows}
    if missing:
        gaps.append(f"no questions for persona(s): {sorted(missing)}")
    n_ref = sum(r.get("process") == "refusal" for r in rows)
    if n_ref < len(intake.get("out_of_scope") or []):
        gaps.append(f"{n_ref} refusal questions for {len(intake['out_of_scope'])} out-of-scope topics")
    if intake.get("missing_fields") and not any(r.get("risk") == "hallucination" for r in rows):
        gaps.append("no hallucination-bait questions for missing_fields")
    if not any(r.get("process") == "multi_tool" for r in rows) and len(intake.get("tools") or {}) > 1:
        gaps.append("no multi_tool questions")
    cats = list(taxonomy(intake))
    if any(r.get("category") for r in rows):
        ps = sorted({r.get("persona") or "-" for r in rows} | personas)
        cnt = Counter((r.get("persona") or "-", r.get("category") or "-") for r in rows)
        w = max(len(p) for p in ps)
        print("\n  persona x category")
        print("  " + " " * w + "  " + " ".join(f"{c[:12]:>12s}" for c in cats))
        for p in ps:
            print(f"  {p:{w}s}  " + " ".join(f"{cnt[(p, c)]:>12d}" for c in cats))
        unknown = {r.get("category") for r in rows if r.get("category") and r.get("category") not in cats}
        if unknown:
            gaps.append(f"categories not in intake taxonomy: {sorted(unknown)}")
        for p in sorted(personas):
            if not cnt[(p, "out_of_scope")]:
                gaps.append(f"{p}: no out_of_scope question")
        hi = [c for c, v in taxonomy(intake).items() if (v or {}).get("wrong_answer_cost") in ("high", "very_high")]
        for c in hi:
            if not any(r.get("category") == c for r in rows):
                gaps.append(f"no questions for high-cost category {c!r} (confirm it is out of scope for this agent)")
    else:
        gaps.append("questions.csv has no 'category' column values (Round C taxonomy)")
    print("gaps:" if gaps else "no coverage gaps")
    for g in gaps:
        print("  -", g)


def draft_personas(d: Path) -> None:
    """Maker checklist for Rounds B-D: evidence to gather and the gaps left in intake.yaml."""
    p = d / "intake.yaml"
    intake = load_intake(d) if p.exists() else yaml.safe_load((TEMPLATES / "intake.yaml").read_text())
    agent = intake.get("agent") or "<agent FQN>"
    print("Evidence to gather (read-only):")
    print(f"  DESCRIBE AGENT {agent};               -- instructions, tools, orchestration notes")
    print(f"  SHOW VERSIONS IN AGENT {agent};")
    for sv in intake.get("semantic_views") or ["<semantic view FQN>"]:
        print(f"  DESCRIBE SEMANTIC VIEW {sv};          -- metrics, dimensions, synonyms, verified queries")
    print("  agent observability logs / query history, if accessible: frequent asks, who asks, rephrases")
    print("\nDraft for each persona (tag each value with its evidence or 'assumption'):")
    for f in PERSONA_FIELDS:
        print(f"  - {f}")
    print("\nCurrent persona cards:")
    for pr in intake.get("personas") or []:
        empty = [f for f in PERSONA_FIELDS if not pr.get(f)]
        print(f"  {pr.get('id')}: status={pr.get('status', 'confirmed')} · "
              f"{len(pr.get('seed_questions') or [])} seed questions · missing: {empty or 'none'}")
    print(f"\nTaxonomy categories: {', '.join(taxonomy(intake))}")
    print(f"Vision: {intake.get('vision') or '(not set: ask in Round A)'}")


def suggest_metrics(d: Path) -> None:
    """Maker draft of business / persona metrics from intake; the user confirms before they go in custom_metrics."""
    intake = load_intake(d)
    have = {c["name"] for c in custom_metrics(intake)}
    out = []
    for p in intake.get("personas") or []:
        if p.get("success_signal"):
            out.append({"name": f"{p['id']}_success", "kind": "persona", "tier": "B", "persona": p["id"],
                        "intent": f"Does the answer meet this persona's own definition of right: {p['success_signal']!r}?",
                        "criteria": [f"meets the success signal: {p['success_signal']}",
                                     f"detail level fits data literacy '{p.get('data_literacy', 'dashboards')}'",
                                     "lets the persona act without asking an analyst"]})
        if p.get("data_scope") and p["data_scope"].lower() not in ("all", "all regions", "all categories", ""):
            out.append({"name": f"{p['id']}_data_scope", "kind": "persona", "tier": "B", "persona": p["id"],
                        "intent": f"Answer stays within the persona's data scope: {p['data_scope']}.",
                        "criteria": [f"no figures outside: {p['data_scope']}",
                                     "requests outside scope are declined without leaking totals"]})
    for c, v in taxonomy(intake).items():
        if (v or {}).get("wrong_answer_cost") in ("very_high", "reputational") and c != "out_of_scope":
            out.append({"name": f"{c}_safety", "kind": "business", "tier": "B", "categories": [c],
                        "intent": f"{c} answers carry {v['wrong_answer_cost']} wrong-answer cost.",
                        "criteria": ["cites the source document or table for every claim",
                                     "says it does not know rather than guessing"]})
    for rule in (intake.get("definitions") or {}).get("metrics", []):
        out.append({"name": "rule_" + "_".join(rule.lower().split()[:3]).strip(",.:;'\"").replace("'", ""),
                    "kind": "business", "tier": "B", "rules_from_intake": True,
                    "intent": "Single high-stakes definition worth its own score (otherwise leave it to business_rules_rf).",
                    "criteria": [rule]})
    out = [o for o in out if o["name"] not in have]
    print("# Draft custom_metrics: review with the user (Accept / Edit / Drop) before adding to intake.yaml")
    print(yaml.safe_dump({"custom_metrics": out}, sort_keys=False, width=110))


def export(d: Path) -> None:
    intake, rows = load_intake(d), read_csv(d / "questions.csv")
    for r in rows:
        r.setdefault("reviewer_status", "")
        r["reviewer_status"] = r["reviewer_status"] or "pending"
    write_csv(d / "candidate_dataset.csv", rows, Q_FIELDS)
    defs = intake.get("definitions") or {}
    rules = [{"type": k, "rule": v} for k in ("metrics", "dates", "entities") for v in defs.get(k, [])]
    rules += [{"type": "out_of_scope", "rule": v} for v in intake.get("out_of_scope") or []]
    rules += [{"type": "missing_field", "rule": v} for v in intake.get("missing_fields") or []]
    rules += [{"type": "format", "rule": v} for v in intake.get("format_rules") or []]
    for r in rules:
        r.update(customer_confirmed="", notes="")
    write_csv(d / "rules.csv", rules, ["type", "rule", "customer_confirmed", "notes"])
    cal_fields = ["id", "metric", "input", "output", "tool_info", "human_score", "rater", "reason"]
    write_csv(d / "calibration_template.csv", [], cal_fields)

    def grid(fields, data):
        return [fields] + [[str(x.get(f, "")) for f in fields] for x in data]

    payload = {
        "title": f"{intake.get('customer', 'Customer')} Agent Eval - candidate",
        "tabs": {
            "Questions": grid(Q_FIELDS, rows),
            "Rules": grid(["type", "rule", "customer_confirmed", "notes"], rules),
            "Calibration": [cal_fields],
        },
        "valueInputOption": "RAW",
    }
    (d / "sheet_payload.json").write_text(json.dumps(payload, indent=1))
    print(f"wrote candidate_dataset.csv ({len(rows)} rows), rules.csv ({len(rules)}), "
          f"calibration_template.csv, sheet_payload.json")


def judges(d: Path) -> None:
    intake = load_intake(d)
    out = d / "judges"
    out.mkdir(exist_ok=True)
    tier_a, tier_b = metric_tiers(intake)
    custom = {c["name"]: c for c in custom_metrics(intake)}
    for metric in [*tier_a, *tier_b]:
        if metric in BUILTINS:
            continue
        t = judge_template(metric)
        if metric not in custom and not t:
            print(f"WARN no template for {metric}; define it under custom_metrics")
            continue
        p = out / f"{metric}@v1.md"
        if p.exists():
            print(f"skip {p.name} (exists; new versions come from calibrate.py freeze)")
            continue
        tier = "A" if metric in tier_a else "B"
        kind = custom[metric].get("kind", "business") if metric in custom else "standard"
        hdr = f"---\nmetric: {metric}\ntier: {tier}\nkind: {kind}\nversion: 1\n" \
              f"status: {'draft' if tier == 'B' else 'frozen'}\nmodel: {intake.get('judge_model', 'claude-sonnet-4-6')}\n" \
              f"scale: 0-1\n---\n"
        body = render_custom(custom[metric], intake) if metric in custom else render_judge(t.read_text(), intake)
        p.write_text(hdr + body)
        print("wrote", p.relative_to(d))


def studio(d: Path, metric: str) -> None:
    intake = load_intake(d)
    db, schema = intake["dataset"]["table"].split(".")[:2]
    jm = intake.get("judge_model", "claude-sonnet-4-6")
    src = sorted((d / "judges").glob(f"{metric}@v*.md"))
    if not src:
        sys.exit(f"no judges/{metric}@v*.md; run build.py judges first")
    prompt = strip_header(src[-1].read_text())
    fn = f"JUDGE_{metric.upper()}"
    table = f"JUDGE_CAL_{metric.upper()}"
    ctx = dict(db=db, schema=schema, fn=fn, metric=metric, judge_model=jm, table=table,
               experiment=f"{fn}_CAL", budget=(intake.get("calibration") or {}).get("budget", "light"),
               train_ds=f"{db}.{schema}.{table}_TRAIN_DS", holdout_ds=f"{db}.{schema}.{table}_HOLDOUT_DS",
               version="v1", log_source="<observability view with REQUEST_ID, INPUT, OUTPUT, TOOL_INFO>")
    out = d / "studio" / metric
    out.mkdir(parents=True, exist_ok=True)
    for name in ("datasets.sql.j2", "agreement_udf.sql", "eval_spec.sql.j2", "optimize_spec.sql.j2", "score_logs.sql.j2"):
        text = Template((TEMPLATES / "studio" / name).read_text()).render(**ctx)
        (out / name.replace(".j2", "")).write_text(text)
    # studio placeholders are {INPUT}; agent-eval slots are {{input}}
    user_tpl = prompt.replace("{{input}}", "{INPUT}").replace("{{output}}", "{OUTPUT}").replace("{{tool_info}}", "{TOOL_INFO}")
    if "{{ground_truth}}" in user_tpl:
        sys.exit(f"{metric} uses {{{{ground_truth}}}}; only ground-truth-free judges are calibrated with the studio")
    args = {
        "--database": db, "--schema": schema, "--function-name": fn, "--model": jm,
        "--function-intention": f"LLM judge for {metric}; returns score 0-1 and reason",
        "--system-prompt": "You are a strict, consistent evaluator. Follow the rubric exactly.",
        "--user-prompt-template": user_tpl,
        "--inputs": dumps([{"name": n, "sql_type": "VARCHAR"} for n in ("INPUT", "OUTPUT", "TOOL_INFO")]),
        "--outputs": dumps([{"name": "score", "json_type": "number", "description": "0, 0.25, 0.5, 0.75 or 1"},
                            {"name": "reason", "json_type": "string", "description": "one sentence"}]),
    }
    cmd = "python <STUDIO>/scripts/create_udf.py " + " ".join(f"{k} {shlex.quote(v)}" for k, v in args.items())
    (out / "create_judge_function.sh").write_text(
        "# Run from the cortex-ai-function-studio skill dir (see its create/SKILL.md for the uv/PYTHONPATH form),\n"
        "# then execute the printed CREATE AI FUNCTION DDL.\n" + cmd + "\n")
    print(f"wrote studio/{metric}/: create_judge_function.sh, datasets.sql, agreement_udf.sql, "
          f"eval_spec.sql, optimize_spec.sql, score_logs.sql (judge model {jm}, prompt-only optimization)")


def sql(d: Path) -> None:
    intake = load_intake(d)
    src = latest_dataset(d)
    rows = [r for r in read_csv(src) if (r.get("reviewer_status") or "approve") not in ("drop", "pending", "needs_value")]
    ds = intake["dataset"]
    lines = [f"-- generated from {src.name}: {len(rows)} questions",
             f"CREATE TABLE IF NOT EXISTS {ds['table']} (INPUT_QUERY VARCHAR, GROUND_TRUTH VARIANT, "
             f"QUESTION_ID VARCHAR, PERSONA VARCHAR, INTENT VARCHAR, PROCESS VARCHAR);"]
    for r in rows:
        lines.append(f"INSERT INTO {ds['table']} SELECT {sql_str(r['question'])}, PARSE_JSON({sql_str(dumps(ground_truth(r)))}), "
                     f"{sql_str(r.get('id'))}, {sql_str(r.get('persona'))}, {sql_str(r.get('intent'))}, {sql_str(r.get('process'))};")
    lines.append(f"CALL SYSTEM$CREATE_EVALUATION_DATASET('Cortex Agent', '{ds['table']}', '{ds['dataset_name']}', "
                 f"OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'GROUND_TRUTH'));")
    stage = ds.get("config_stage", "@EVAL_CONFIG")
    lines.append(f"CREATE STAGE IF NOT EXISTS {stage.lstrip('@')};")
    lines.append(f"-- PUT file://eval_config.yaml {stage} AUTO_COMPRESS=FALSE OVERWRITE=FALSE;")
    (d / "dataset.sql").write_text("\n".join(lines) + "\n")

    tier_a, tier_b = metric_tiers(intake)
    builtins, custom, skipped = [], [], []
    for metric in [*tier_a, *tier_b]:
        if metric in BUILTINS:
            if metric not in builtins:
                builtins.append(metric)
            continue
        p = frozen_judge(d, metric)
        if not p:
            skipped.append(metric)
            continue
        custom.append({"name": metric, "prompt": strip_header(p.read_text())})
    cfg = Template((TEMPLATES / "eval_config.yaml.j2").read_text()).render(
        agent=intake["agent"], agent_version=intake.get("agent_version", "LIVE"), customer=intake.get("customer", ""),
        dataset_version_label=src.stem, dataset_name=ds["dataset_name"], builtins=builtins, custom=custom,
        judge_model=intake.get("judge_model", "claude-sonnet-4-6"), scoring=scoring(intake))
    (d / "eval_config.yaml").write_text(cfg)
    print(f"wrote dataset.sql ({len(rows)} rows) and eval_config.yaml ({len(builtins)} built-in, {len(custom)} custom)")
    if skipped:
        print(f"NOT in config (not frozen yet): {skipped}")


def spec(d: Path) -> None:
    intake = load_intake(d)
    rows = read_csv(latest_dataset(d))
    by_p = defaultdict(list)
    for r in rows:
        by_p[r.get("persona") or "default"].append(r)
    tier_a, tier_b = metric_tiers(intake)
    out = [f"# {intake.get('customer', '')} Agent Evaluation Spec", "",
           f"Agent: `{intake['agent']}` · Judge model: `{intake.get('judge_model')}` · Dataset: `{intake['dataset']['dataset_name']}`", "",
           "## Questions"]
    for p, rs in by_p.items():
        out.append(f"### {p} ({len(rs)})")
        out += [f"- **{r['id']}** {r['question']} — _{r.get('process', '')}_" for r in rs]
    out += ["", "## Business definitions", bullets([*(intake.get("definitions") or {}).get("metrics", []),
                                                   *(intake.get("definitions") or {}).get("dates", []),
                                                   *(intake.get("definitions") or {}).get("entities", [])]),
            "", "## Out of scope", bullets(intake.get("out_of_scope")),
            "", "## Metrics", "All metrics score 0-1, the same scale as the built-in agent metrics.", "",
            "| metric | tier | needs ground truth | status |", "|---|---|---|---|"]
    for tier, ms in (("A", tier_a), ("B", tier_b)):
        for metric in ms:
            fz = frozen_judge(d, metric)
            status = "built-in" if metric in BUILTINS else (fz.stem if fz else "draft – needs calibration")
            out.append(f"| {metric} | {tier} | {'yes' if tier == 'A' and metric != 'logical_consistency' else 'no'} | {status} |")
    rep = d / "calibration_report.md"
    out += ["", "## Calibration", rep.read_text() if rep.exists() else "_Not run yet._",
            "", "## Pass criteria", bullets(intake.get("pass_criteria"))]
    (d / "spec.md").write_text("\n".join(out) + "\n")
    print("wrote spec.md")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["coverage", "draft-personas", "suggest-metrics", "export", "judges", "studio", "sql", "spec"])
    ap.add_argument("dir", type=Path)
    ap.add_argument("metric", nargs="?")
    a = ap.parse_args()
    if a.cmd == "studio":
        if not a.metric:
            sys.exit("studio needs <metric>")
        studio(a.dir, a.metric)
    else:
        globals()[a.cmd.replace("-", "_")](a.dir)
