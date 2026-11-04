"""Preflight checks before materializing a dataset / eval config.  lint.py <dir>   (exit 1 on any ERROR)"""
from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent))
from common import (BUILTINS, GT_INVOCATION_METRICS, PLACEHOLDER, RELATIVE, frozen_judge, latest_dataset,  # noqa: E402
                    load_intake, metric_tiers, read_csv, scoring, taxonomy)


def main(d: Path) -> int:
    intake = load_intake(d)
    src = latest_dataset(d)
    rows = [r for r in read_csv(src) if (r.get("reviewer_status") or "approve") not in ("drop",)]
    errs, warns = [], []
    tier_a, tier_b = metric_tiers(intake)
    jm = intake.get("judge_model")
    if not jm:
        errs.append("intake.judge_model is not set")

    for r in rows:
        rid, gt = r.get("id"), (r.get("ground_truth_output") or "").strip()
        st = (r.get("reviewer_status") or "").lower()
        if st in ("pending", "needs_value"):
            warns.append(f"{rid}: reviewer_status={st} (excluded from dataset.sql)")
            continue
        if not gt and r.get("process") != "refusal":
            errs.append(f"{rid}: empty ground_truth_output")
        if PLACEHOLDER.search(gt):
            errs.append(f"{rid}: placeholder in ground truth: {PLACEHOLDER.search(gt).group(0)!r}")
        if r.get("process") != "refusal" and gt and not re.search(r"\d", gt):
            warns.append(f"{rid}: ground truth has no literal number (rubric-only?)")
        rel_q = RELATIVE.search(r.get("question") or "")
        if rel_q and not (r.get("pinned_date") or "").strip() and r.get("process") != "refusal":
            if any(x in tier_a for x in ("answer_correctness",)):
                errs.append(f"{rid}: relative date {rel_q.group(0)!r} without pinned_date; ground truth will go stale")
        if GT_INVOCATION_METRICS & set(tier_a) and not (r.get("expected_tools") or "").strip() and r.get("process") != "refusal":
            errs.append(f"{rid}: tool selection/execution metrics selected but expected_tools empty")
        if "efficiency" in tier_a and (r.get("min_data_calls") or "").strip() == "":
            errs.append(f"{rid}: efficiency metric selected but min_data_calls empty")

    qs = [(r.get("id"), (r.get("question") or "").lower().strip()) for r in rows]
    for i in range(len(qs)):
        for j in range(i + 1, len(qs)):
            ratio = difflib.SequenceMatcher(None, qs[i][1], qs[j][1]).ratio()
            if ratio > 0.92:
                warns.append(f"near-duplicate questions {qs[i][0]} / {qs[j][0]} ({ratio:.2f})")

    personas = {p["id"] for p in intake.get("personas", [])}
    for p in intake.get("personas", []):
        if p.get("status") == "drafted":
            warns.append(f"persona {p['id']}: status=drafted (not confirmed by the customer)")
        if not p.get("success_signal"):
            warns.append(f"persona {p['id']}: no success_signal (their definition of a right answer)")
        if "seed_questions" in p and not p.get("seed_questions"):
            warns.append(f"persona {p['id']}: no seed_questions")
    if not intake.get("vision"):
        warns.append("intake.vision is empty (Round A)")
    cats = taxonomy(intake)
    if any(r.get("category") for r in rows):
        for r in rows:
            if (r.get("category") or "") not in cats:
                warns.append(f"{r.get('id')}: category {r.get('category')!r} not in intake taxonomy")
        for c in cats:
            if not any(r.get("category") == c for r in rows):
                warns.append(f"taxonomy category {c!r} has no questions")
    if personas - {r.get("persona") for r in rows}:
        warns.append(f"personas with no questions: {sorted(personas - {r.get('persona') for r in rows})}")
    if intake.get("out_of_scope") and not any(r.get("process") == "refusal" for r in rows):
        errs.append("out_of_scope defined but no refusal questions")

    for metric in tier_b:
        if metric in BUILTINS:
            continue
        if not frozen_judge(d, metric):
            warns.append(f"Tier B {metric}: not calibrated/frozen; it will be left out of eval_config.yaml")
    for p in (d / "judges").glob("*.md"):
        t = p.read_text()
        if "{{ground_truth}}" in t and any(p.name.startswith(b + "@") for b in tier_b):
            errs.append(f"{p.name}: Tier B judge references {{{{ground_truth}}}}")
        hdr = t.split("---", 2)[1] if t.startswith("---") else ""
        if "{0, 0.25, 0.5, 0.75, 1}" not in t and not re.search(r"\b0\.(25|5)\b", t):
            errs.append(f"{p.name}: judge does not score on the 0-1 band scale used by the built-in metrics")
        mm = re.search(r"model:\s*(\S+)", hdr)
        if mm and jm and mm.group(1) != jm:
            errs.append(f"{p.name}: judge model {mm.group(1)} != intake judge_model {jm} (re-calibrate)")
    names = [*tier_a, *tier_b]
    for n in {x for x in names if names.count(x) > 1}:
        errs.append(f"metric {n} listed twice (metrics + custom_metrics?)")
    for c in intake.get("custom_metrics") or []:
        if not c.get("criteria"):
            errs.append(f"custom metric {c.get('name')}: no criteria")
        if c.get("persona") and c["persona"] not in personas:
            errs.append(f"custom metric {c['name']}: unknown persona {c['persona']!r}")
        if str(c.get("tier", "B")).upper() == "B" and "{{ground_truth}}" in str(c):
            errs.append(f"custom metric {c['name']}: Tier B must not use ground truth")
    sr = scoring(intake)["score_ranges"]
    if sr["min_score"][0] != 0 or sr["max_score"][1] != 1:
        errs.append(f"scoring.score_ranges must span 0-1 like the built-in metrics: {sr}")
    cfg = d / "eval_config.yaml"
    if cfg.exists():
        for met in (yaml.safe_load(cfg.read_text()) or {}).get("metrics", []):
            if isinstance(met, dict) and met.get("model") and met["model"] != jm:
                errs.append(f"eval_config.yaml: {met.get('name')} uses model {met['model']} != {jm}")

    n_metrics = len(set(tier_a) | {t for t in tier_b if frozen_judge(d, t) or t in BUILTINS})
    per = (intake.get("cost") or {}).get("credits_per_question_metric", 0.5)
    print(f"{src.name}: {len(rows)} rows · {n_metrics} metrics in config · judge {jm}")
    print(f"rough eval cost: {len(rows)} x {n_metrics} x {per} ≈ {len(rows) * n_metrics * per:.0f} credits per agent "
          f"version (plus agent tool warehouse); refine credits_per_question_metric from past runs")
    for w_ in warns:
        print("WARN ", w_)
    for e in errs:
        print("ERROR", e)
    print("OK" if not errs else f"{len(errs)} error(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))
