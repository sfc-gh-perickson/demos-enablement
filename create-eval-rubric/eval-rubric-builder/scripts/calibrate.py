"""Judge calibration against human scores.

  calibrate.py split  <dir> [--holdout 0.3] [--seed 7]
      reads calibration_labels.csv (id, metric, input, output, tool_info, human_score[, rater, reason]);
      averages multiple raters, reports inter-rater agreement, writes studio/<metric>/{train,holdout}.csv
  calibrate.py report <dir> <metric> <predictions.csv> [--label baseline|optimized]
      predictions.csv: id, judge_score (holdout rows); appends to calibration_report.md, exit 1 if gate fails
  calibrate.py freeze <dir> <metric> --prompt-file F --experiment E --run R
      writes judges/<metric>@v<N+1>.md with status: frozen (requires a passing report)
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import load_intake, read_csv, write_csv  # noqa: E402

BANDS = [0.0, 0.25, 0.5, 0.75, 1.0]


def band(x: float) -> int:
    return min(range(len(BANDS)), key=lambda i: abs(BANDS[i] - x))


def weighted_kappa(a: list[int], b: list[int], k: int = len(BANDS)) -> float:
    """Quadratic-weighted Cohen's kappa."""
    n = len(a)
    if n == 0:
        return float("nan")
    obs = [[0] * k for _ in range(k)]
    for x, y in zip(a, b):
        obs[x][y] += 1
    ra = [sum(r) for r in obs]
    cb = [sum(obs[i][j] for i in range(k)) for j in range(k)]
    num = den = 0.0
    for i in range(k):
        for j in range(k):
            w = (i - j) ** 2 / (k - 1) ** 2
            num += w * obs[i][j]
            den += w * ra[i] * cb[j] / n
    return 1.0 if den == 0 else 1 - num / den


def spearman(a: list[float], b: list[float]) -> float:
    def ranks(v):
        order = sorted(range(len(v)), key=lambda i: v[i])
        r = [0.0] * len(v)
        i = 0
        while i < len(v):
            j = i
            while j + 1 < len(v) and v[order[j + 1]] == v[order[i]]:
                j += 1
            for t in range(i, j + 1):
                r[order[t]] = (i + j) / 2
            i = j + 1
        return r
    ra, rb = ranks(a), ranks(b)
    n = len(a)
    ma, mb = sum(ra) / n, sum(rb) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    va = sum((x - ma) ** 2 for x in ra) ** 0.5
    vb = sum((y - mb) ** 2 for y in rb) ** 0.5
    return float("nan") if va == 0 or vb == 0 else cov / (va * vb)


def parse_score(v: str) -> float | None:
    v = (v or "").strip()
    if not v:
        return None
    try:
        o = json.loads(v)
        if isinstance(o, dict):
            o = o.get("score")
        return float(o)
    except (ValueError, TypeError):
        m = re.search(r"-?\d+(?:\.\d+)?", v)
        return float(m.group()) if m else None


def split(d: Path, holdout: float, seed: int) -> None:
    rows = read_csv(d / "calibration_labels.csv")
    groups = defaultdict(list)
    for r in rows:
        s = parse_score(r.get("human_score"))
        if s is not None:
            groups[(r["metric"], r["id"])].append((r.get("rater") or "r1", s, r))
    by_metric = defaultdict(list)
    for (metric, _), labels in groups.items():
        raters = {}
        for rater, s, _r in labels:
            raters[rater] = s
        base = dict(labels[0][2])
        base["human_score"] = round(sum(raters.values()) / len(raters), 4)
        base["_raters"] = raters
        by_metric[metric].append(base)
    min_rows = (load_intake(d).get("calibration") or {}).get("min_rows", 20)
    rng = random.Random(seed)
    for metric, items in by_metric.items():
        # inter-rater agreement on rows with 2+ raters
        pairs = [list(r["_raters"].values())[:2] for r in items if len(r["_raters"]) >= 2]
        irr = (f"inter-rater weighted kappa {weighted_kappa([band(p[0]) for p in pairs], [band(p[1]) for p in pairs]):.2f} "
               f"on {len(pairs)} rows") if pairs else "single rater (no inter-rater check)"
        strata = defaultdict(list)
        for r in items:
            strata[band(r["human_score"])].append(r)
        train, hold = [], []
        for _, rs in sorted(strata.items()):
            rng.shuffle(rs)
            k = max(1, round(len(rs) * holdout)) if len(rs) > 1 else 0
            hold += rs[:k]
            train += rs[k:]
        out = d / "studio" / metric
        out.mkdir(parents=True, exist_ok=True)
        f = ["id", "input", "output", "tool_info", "human_score"]
        write_csv(out / "train.csv", train, f)
        write_csv(out / "holdout.csv", hold, f)
        warn = f"  WARN only {len(items)} labeled rows (< {min_rows})" if len(items) < min_rows else ""
        dist = {BANDS[b]: len(v) for b, v in sorted(strata.items())}
        print(f"{metric}: {len(train)} train / {len(hold)} holdout · bands {dist} · {irr}{warn}")


def report(d: Path, metric: str, preds: Path, label: str) -> None:
    intake = load_intake(d)
    cal = intake.get("calibration") or {}
    kmin, amin = cal.get("kappa_min", 0.6), cal.get("agreement_min", 0.8)
    hold = {r["id"]: r for r in read_csv(d / "studio" / metric / "holdout.csv")}
    pairs = []
    for p in read_csv(preds):
        if p["id"] in hold:
            j = parse_score(p.get("judge_score"))
            if j is not None:
                pairs.append((p["id"], float(hold[p["id"]]["human_score"]), j))
    if not pairs:
        sys.exit("no predictions match holdout ids")
    hb, jb = [band(h) for _, h, _ in pairs], [band(j) for _, _, j in pairs]
    kappa = weighted_kappa(hb, jb)
    agree = sum(x == y for x, y in zip(hb, jb)) / len(pairs)
    rho = spearman([h for _, h, _ in pairs], [j for _, _, j in pairs])
    mae = sum(abs(h - j) for _, h, j in pairs) / len(pairs)
    bias = sum(j - h for _, h, j in pairs) / len(pairs)
    ok = kappa >= kmin and agree >= amin
    used = sorted(set(hb) | set(jb))
    conf = ["| human \\ judge | " + " | ".join(str(BANDS[b]) for b in used) + " |",
            "|---" * (len(used) + 1) + "|"]
    for hbv in used:
        conf.append(f"| {BANDS[hbv]} | " + " | ".join(str(sum(1 for x, y in zip(hb, jb) if x == hbv and y == c)) for c in used) + " |")
    dis = sorted([(abs(h - j), i, h, j) for i, h, j in pairs if band(h) != band(j)], reverse=True)[:10]
    lines = [f"### {metric} – {label} ({dt.date.today()})",
             f"judge model `{intake.get('judge_model')}` · n={len(pairs)} holdout",
             f"- weighted kappa **{kappa:.2f}** (min {kmin}) · exact-band agreement **{agree:.0%}** (min {amin:.0%})",
             f"- Spearman {rho:.2f} · MAE {mae:.2f} · bias {bias:+.2f} ({'lenient' if bias > 0.05 else 'strict' if bias < -0.05 else 'unbiased'} vs humans)",
             f"- gate: **{'PASS' if ok else 'FAIL'}**", "", *conf, ""]
    if dis:
        lines.append("Largest disagreements (id, human, judge): " + "; ".join(f"{i} {h}->{j}" for _, i, h, j in dis))
    lines.append("")
    text = "\n".join(lines)
    with open(d / "calibration_report.md", "a") as f:
        f.write(text + "\n")
    (d / "studio" / metric / f"report_{label}.json").write_text(json.dumps(
        {"kappa": kappa, "agreement": agree, "spearman": rho, "mae": mae, "bias": bias, "pass": ok, "n": len(pairs)}))
    print(text)
    sys.exit(0 if ok else 1)


def freeze(d: Path, metric: str, prompt_file: Path, experiment: str, run: str) -> None:
    intake = load_intake(d)
    rep = d / "studio" / metric / "report_optimized.json"
    if not rep.exists():
        rep = d / "studio" / metric / "report_baseline.json"
    if not rep.exists() or not json.loads(rep.read_text())["pass"]:
        sys.exit("no passing calibration report for this metric; run calibrate.py report first")
    r = json.loads(rep.read_text())
    prompt = prompt_file.read_text()
    prompt = prompt.replace("{INPUT}", "{{input}}").replace("{OUTPUT}", "{{output}}").replace("{TOOL_INFO}", "{{tool_info}}")
    missing = [s for s in ("{{input}}", "{{output}}") if s not in prompt]
    if missing:
        sys.exit(f"optimized prompt lacks slots {missing}; map the studio argument names back to agent-eval slots")
    vs = [int(p.stem.split("@v")[1]) for p in (d / "judges").glob(f"{metric}@v*.md")]
    n = max(vs, default=0) + 1
    hdr = (f"---\nmetric: {metric}\ntier: B\nversion: {n}\nstatus: frozen\nmodel: {intake.get('judge_model')}\n"
           f"calibrated: {dt.date.today()}\nkappa: {r['kappa']:.3f}\nagreement: {r['agreement']:.3f}\nn_holdout: {r['n']}\n"
           f"experiment: {experiment}\nrun: {run}\n---\n")
    out = d / "judges" / f"{metric}@v{n}.md"
    out.write_text(hdr + prompt.strip() + "\n")
    print("froze", out.relative_to(d))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["split", "report", "freeze"])
    ap.add_argument("dir", type=Path)
    ap.add_argument("metric", nargs="?")
    ap.add_argument("predictions", nargs="?", type=Path)
    ap.add_argument("--holdout", type=float, default=None)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--label", default="optimized")
    ap.add_argument("--prompt-file", type=Path)
    ap.add_argument("--experiment", default="")
    ap.add_argument("--run", default="")
    a = ap.parse_args()
    if a.cmd == "split":
        h = a.holdout if a.holdout is not None else (load_intake(a.dir).get("calibration") or {}).get("holdout", 0.3)
        split(a.dir, h, a.seed)
    elif a.cmd == "report":
        report(a.dir, a.metric, a.predictions, a.label)
    else:
        freeze(a.dir, a.metric, a.prompt_file, a.experiment, a.run)
