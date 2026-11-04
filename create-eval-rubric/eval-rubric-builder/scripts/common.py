"""Shared helpers for eval-rubric-builder scripts."""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

import yaml

SKILL = Path(__file__).resolve().parent.parent
TEMPLATES = SKILL / "templates"
SLOTS = ("input", "output", "tool_info", "ground_truth", "duration")
BUILTINS = {"answer_correctness", "logical_consistency", "tool_selection_accuracy", "tool_execution_accuracy"}
GT_INVOCATION_METRICS = {"tool_selection_accuracy", "tool_execution_accuracy"}
GT_METRICS = {"answer_correctness", "business_rules", "efficiency"} | GT_INVOCATION_METRICS
PLACEHOLDER = re.compile(r"\b(TBD|TODO|XXX)\b|<[a-z_ ]+>|\b[XYZ]\b(?=[,.%\s]|$)|\?\?")
RELATIVE = re.compile(r"\b(today|yesterday|tomorrow|last (week|month|quarter|year)|this (week|month|quarter|year)|"
                      r"[MQYW]TD|month to date|year to date|quarter to date|past \d+ days|recent(ly)?)\b", re.I)
DEFAULT_TAXONOMY = {
    "lookup": {"complexity": "low", "data_source": "structured", "wrong_answer_cost": "medium"},
    "aggregation": {"complexity": "medium", "data_source": "structured", "wrong_answer_cost": "high"},
    "reasoning": {"complexity": "high", "data_source": "structured+unstructured", "wrong_answer_cost": "high"},
    "policy_process": {"complexity": "low", "data_source": "unstructured", "wrong_answer_cost": "very_high"},
    "out_of_scope": {"complexity": "n/a", "data_source": "n/a", "wrong_answer_cost": "reputational"},
}
PERSONA_FIELDS = ("role", "decisions", "data_literacy", "workflow", "frequency", "stakes", "success_signal", "data_scope")
# Built-in agent metrics report normalized_score in [0.0, 1.0]; every judge here uses the same scale.
BANDS = (0.0, 0.25, 0.5, 0.75, 1.0)
DEFAULT_SCORING = {
    "builtin_version": "v3",   # v3 judge = claude-sonnet-4-6, same as judge_model
    "bands": list(BANDS),
    "score_ranges": {"min_score": [0, 0.4], "median_score": [0.4, 0.7], "max_score": [0.7, 1]},
}
SCORE_FORMAT = ("Use the same 0-1 scale as the built-in agent metrics. Reply with exactly one score from "
                "{0, 0.25, 0.5, 0.75, 1} first, then one sentence of reason.")


def scoring(intake: dict) -> dict:
    return {**DEFAULT_SCORING, **(intake.get("scoring") or {})}


def custom_metrics(intake: dict) -> list[dict]:
    return intake.get("custom_metrics") or []


def metric_tiers(intake: dict) -> tuple[list[str], list[str]]:
    """Tier A / Tier B metric names, including intake-defined business and persona metrics."""
    m = intake.get("metrics") or {}
    a, b = list(m.get("tier_a", [])), list(m.get("tier_b", []))
    for c in custom_metrics(intake):
        (a if str(c.get("tier", "B")).upper() == "A" else b).append(c["name"])
    return a, b


def taxonomy(intake: dict) -> dict:
    return intake.get("taxonomy") or DEFAULT_TAXONOMY


def persona_line(p: dict) -> str:
    """One judge-ready line per persona; older intakes with only description/data_scope still work."""
    parts = [p.get("description") or p.get("role") or ""]
    for k, label in (("data_literacy", "literacy"), ("stakes", "stakes"), ("success_signal", "success signal")):
        if p.get(k):
            parts.append(f"{label}: {p[k]}")
    parts.append(f"data scope: {p.get('data_scope') or 'all'}")
    return "; ".join(x for x in parts if x)


def load_intake(d: Path) -> dict:
    return yaml.safe_load((d / "intake.yaml").read_text())


def read_csv(p: Path) -> list[dict]:
    with open(p, newline="") as f:
        return list(csv.DictReader(f))


def write_csv(p: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    fields = fields or (list(rows[0].keys()) if rows else [])
    with open(p, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        wr.writeheader()
        wr.writerows(rows)


def bullets(items) -> str:
    if not items:
        return "- (none specified)"
    if isinstance(items, dict):
        return "\n".join(f"- {k}: {v}" for k, v in items.items())
    return "\n".join(f"- {i}" for i in items)


def render_judge(text: str, intake: dict) -> str:
    """Fill intake-derived blocks; leave agent-eval slots ({{input}} etc.) untouched."""
    defs = intake.get("definitions") or {}
    rules = [*defs.get("metrics", []), *defs.get("dates", []), *defs.get("entities", [])]
    personas = {p["id"]: persona_line(p) for p in intake.get("personas", [])}
    values = {
        "domain": intake.get("domain") or "analytics",
        "rules_block": bullets(rules),
        "dates_block": bullets(defs.get("dates")),
        "tools_block": bullets(intake.get("tools")),
        "out_of_scope_block": bullets(intake.get("out_of_scope")),
        "missing_fields_block": bullets(intake.get("missing_fields")),
        "format_block": bullets(intake.get("format_rules")),
        "personas_block": bullets(personas),
        "as_of_date": str((intake.get("dataset") or {}).get("as_of_date", "the evaluation date")),
        "score_format": SCORE_FORMAT,
    }

    def sub(m):
        k = m.group(1).strip()
        return m.group(0) if k in SLOTS else values.get(k, m.group(0))

    return re.sub(r"\{\{\s*([a-z_]+)\s*\}\}", sub, text)


DEFAULT_ANCHORS = {
    1: "every criterion holds",
    0.75: "every criterion holds, with one cosmetic issue that would not change a decision",
    0.5: "one criterion is partly missed",
    0.25: "one criterion clearly fails",
    0: "two or more criteria fail, or any fabricated number or data-scope breach",
}


def render_custom(c: dict, intake: dict) -> str:
    """Judge prompt for an intake-defined business or persona metric (custom_metrics entry)."""
    personas = {p["id"]: p for p in intake.get("personas", [])}
    tier_a = str(c.get("tier", "B")).upper() == "A"
    dom = intake.get("domain") or "analytics"
    lines = [f"You grade {'an' if dom[0].lower() in 'aeiou' else 'a'} {dom} agent on one {c.get('kind', 'business')} metric: "
             f"{c['name']}. {c.get('intent', '')}".rstrip()]
    scope = []
    if c.get("persona"):
        p = personas.get(c["persona"], {"id": c["persona"]})
        scope.append(f"the user is the `{c['persona']}` persona ({persona_line(p)})")
    if c.get("categories"):
        scope.append(f"the question is in categor{'y' if len(c['categories']) == 1 else 'ies'} {', '.join(c['categories'])}")
    if scope:
        lines.append(f"This metric applies only when {' and '.join(scope)}. If it does not apply, score 1 and start "
                     f"the reason with 'N/A:'.")
    lines += ["User question: {{input}}", "Agent answer: {{output}}",
              "Tool calls, generated SQL and tool results: {{tool_info}}"]
    if tier_a:
        lines.append("Expected behaviour: {{ground_truth}}")
    lines += ["", "Criteria:", bullets(c.get("criteria"))]
    if c.get("rules_from_intake"):
        lines += ["Business definitions:", "{{rules_block}}"]
    anchors = {float(k): v for k, v in (c.get("anchors") or DEFAULT_ANCHORS).items()}
    lines += ["", "Score anchors:"] + [f"- {k:g} = {anchors[k]}" for k in sorted(anchors, reverse=True)]
    lines += ["{{score_format}}"]
    return render_judge("\n".join(lines) + "\n", intake)


def judge_template(metric: str) -> Path | None:
    for tier in ("tierA", "tierB"):
        p = TEMPLATES / "judges" / tier / f"{metric}.md"
        if p.exists():
            return p
    return None


def frozen_judge(d: Path, metric: str) -> Path | None:
    """Latest frozen judges/<metric>@vN.md, or None."""
    found = []
    for p in (d / "judges").glob(f"{metric}@v*.md"):
        if "status: frozen" in p.read_text()[:400]:
            found.append((int(p.stem.split("@v")[1]), p))
    return max(found)[1] if found else None


def strip_header(text: str) -> str:
    if text.startswith("---"):
        return text.split("---", 2)[2].lstrip()
    return text


def ground_truth(row: dict) -> dict:
    gt = {"ground_truth_output": (row.get("ground_truth_output") or "").strip()}
    tools = [t.strip() for t in (row.get("expected_tools") or "").split(";") if t.strip()]
    if tools:
        gt["ground_truth_invocations"] = [{"tool_name": t} for t in tools]
    if (row.get("min_data_calls") or "").strip() != "":
        gt["min_data_calls"] = int(row["min_data_calls"])
    return gt


def latest_dataset(d: Path) -> Path:
    vs = sorted(d.glob("dataset_v*.csv"), key=lambda p: int(p.stem.split("_v")[1]))
    return vs[-1] if vs else d / "questions.csv"


def sql_str(s: str) -> str:
    return "'" + (s or "").replace("\\", "\\\\").replace("'", "''") + "'"


def dumps(o) -> str:
    return json.dumps(o, ensure_ascii=False)
