"""Build the scorecard views, aggregate repeats per variant, and compute the Pareto frontier.

Usage: python frontier.py lab.yaml [--runs r1,r2,...] [--alias-map run=alias,...] [--no-views]
  --runs       defaults to <run_prefix>_<name> (plus _r<k> when repeats > 1) for every variant (or runs.json if present)
Outputs <out_dir>/<run_prefix>/frontier.{json,md,svg}.
A variant is "dominated" when another is at least as good on every objective (by mean) and better on one.
It is "dominated (CI-clear)" only when at least one of those wins has non-overlapping 95% intervals;
otherwise "dominated (within noise)". With 1 run per variant there is no interval: say so.
"""
import io
import json
import math
import os
import re
import statistics
import sys

from common import connect, load_lab, render_sql, run_name

T95 = {1: 12.71, 2: 4.30, 3: 3.18, 4: 2.78, 5: 2.57, 6: 2.45, 7: 2.36, 8: 2.31, 9: 2.26}


def arg(name):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None


def view_prefix(lab):
    return f"PARETO_{lab['run_prefix'].upper()}"


def fetch(cur, sql):
    cur.execute(sql)
    cols = [c[0].lower() for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def per_run_rows(lab, cur, runs):
    v = view_prefix(lab)
    cards = {r["eval_run_name"]: r for r in fetch(cur, f"SELECT * FROM {v}_RUN_SCORECARD")}
    out = {}
    for m in fetch(cur, f"SELECT * FROM {v}_RUN_METRICS"):
        row = out.setdefault(m["eval_run_name"], dict(cards.get(m["eval_run_name"], {})))
        row[m["metric_name"]] = float(m["score"]) if m["score"] is not None else None
        if m["metric_name"] in ("answer_correctness", "correctness"):
            row["correct_rate"] = m["n_at_threshold"] / m["n"] if m["n"] else None
            cpr = row.get("credits_per_request")
            row["credits_per_correct_answer"] = (float(cpr) * m["n"] / m["n_at_threshold"]
                                                 if cpr is not None and m["n_at_threshold"] else None)
    for r in runs:
        out.setdefault(r, dict(cards.get(r, {})))
    return {r: {k: (float(x) if isinstance(x, (int, float)) or hasattr(x, "as_tuple") else x)
                for k, x in row.items()} for r, row in out.items()}


def aggregate(lab, rows, alias_of):
    by = {}
    for run, row in rows.items():
        by.setdefault(alias_of[run], []).append(row)
    agg = {}
    metrics = {o["metric"] for o in lab["objectives"]} | set(lab.get("constraints") or {}) | {
        "answer_correctness", "logical_consistency", "credits_per_request", "credits_per_correct_answer",
        "correct_rate", "avg_total_tokens", "avg_duration_s", "p95_duration_s", "avg_planning_steps"}
    for alias, rs in by.items():
        a = {"alias": alias, "runs": len(rs), "billed_fraction": None}
        req = sum(r.get("requests") or 0 for r in rs)
        a["billed_fraction"] = (sum(r.get("requests_billed") or 0 for r in rs) / req) if req else 0
        for m in sorted(metrics):
            vals = [r[m] for r in rs if r.get(m) is not None]
            if not vals:
                continue
            mean = statistics.fmean(vals)
            half = T95.get(len(vals) - 1, 1.96) * statistics.stdev(vals) / math.sqrt(len(vals)) if len(vals) > 1 else None
            a[m] = {"mean": mean, "n": len(vals), "ci95": half}
        agg[alias] = a
    return agg


def better(o, x, y):
    return x > y if o["direction"] == "max" else x < y


def separated(o, a, b):
    if a.get("ci95") is None or b.get("ci95") is None:
        return False
    if o["direction"] == "max":
        return a["mean"] - a["ci95"] > b["mean"] + b["ci95"]
    return a["mean"] + a["ci95"] < b["mean"] - b["ci95"]


def frontier(lab, agg):
    objs = lab["objectives"]
    for a in agg.values():
        a["excluded"] = [f"{m} {k} {lim}" for m, c in (lab.get("constraints") or {}).items() for k, lim in c.items()
                         if m not in a or (k == "min" and a[m]["mean"] < lim) or (k == "max" and a[m]["mean"] > lim)]
        a["missing"] = [o["metric"] for o in objs if o["metric"] not in a]
    elig = [a for a in agg.values() if not a["excluded"] and not a["missing"]]
    for b in elig:
        b["status"], b["dominated_by"] = "frontier", []
        for a in elig:
            if a is b:
                continue
            ge = all(not better(o, b[o["metric"]]["mean"], a[o["metric"]]["mean"]) for o in objs)
            gt = [o for o in objs if better(o, a[o["metric"]]["mean"], b[o["metric"]]["mean"])]
            if ge and gt:
                clear = any(separated(o, a[o["metric"]], b[o["metric"]]) for o in gt)
                b["dominated_by"].append({"alias": a["alias"], "ci_clear": clear})
        if b["dominated_by"]:
            b["status"] = ("dominated (CI-clear)" if any(d["ci_clear"] for d in b["dominated_by"])
                           else "dominated (within noise)" if b["runs"] > 1 else "dominated (n=1, no CI)")
    for a in agg.values():
        if a["excluded"] or a["missing"]:
            a["status"] = "excluded: " + ", ".join(a["excluded"] + [f"missing {m}" for m in a["missing"]])
    return agg


def fmt(m):
    if not m:
        return "—"
    s = f"{m['mean']:.4g}"
    return s + (f" ± {m['ci95']:.2g}" if m.get("ci95") is not None else "")


def tradeoffs(lab, agg):
    front = [a for a in agg.values() if a.get("status") == "frontier"]
    if len(lab["objectives"]) < 2 or len(front) < 2:
        return []
    x, y = lab["objectives"][1]["metric"], lab["objectives"][0]["metric"]
    front.sort(key=lambda a: a[x]["mean"])
    lines = []
    for lo, hi in zip(front, front[1:]):
        lines.append(f"- `{hi['alias']}` vs `{lo['alias']}`: {x} {hi[x]['mean'] - lo[x]['mean']:+.4g}, "
                     f"{y} {hi[y]['mean'] - lo[y]['mean']:+.4g}")
    return lines


def markdown(lab, agg):
    objs = [o["metric"] for o in lab["objectives"]]
    extra = [m for m in ("answer_correctness", "logical_consistency", "credits_per_request", "credits_per_correct_answer",
                         "p95_duration_s", "avg_total_tokens") if m not in objs]
    cols = objs + extra
    lines = [f"# Pareto frontier: {lab['agent']} ({lab['run_prefix']})", "",
             "Objectives: " + ", ".join(f"{o['direction']} {o['metric']}" for o in lab["objectives"]) +
             f". Values are mean ± 95% CI across runs (t-interval).", "",
             "| Variant | Status | Runs | Billed | " + " | ".join(cols) + " |",
             "|---|---|---|---|" + "---|" * len(cols)]
    order = sorted(agg.values(), key=lambda a: (a.get("status") != "frontier", a["alias"]))
    for a in order:
        dom = ", ".join(d["alias"] for d in a.get("dominated_by", []))
        st = a.get("status", "") + (f" by {dom}" if dom else "")
        lines.append(f"| `{a['alias']}` | {st} | {a['runs']} | {a['billed_fraction']:.0%} | " +
                     " | ".join(fmt(a.get(c)) for c in cols) + " |")
    t = tradeoffs(lab, agg)
    if t:
        lines += ["", "Trade-offs between neighbouring frontier variants:"] + t
    warn = [a["alias"] for a in agg.values() if a["billed_fraction"] < 1]
    if warn:
        lines += ["", f"Billing incomplete for {', '.join(warn)}: cost figures are partial (run wait_billing.py)."]
    if any(a["runs"] < 2 for a in agg.values()):
        lines += ["", "Some variants have a single run: no confidence interval, treat small gaps as noise."]
    return "\n".join(lines) + "\n"


def svg(lab, agg):
    if len(lab["objectives"]) < 2:
        return None
    y, x = lab["objectives"][0]["metric"], lab["objectives"][1]["metric"]
    pts = [a for a in agg.values() if x in a and y in a]
    if not pts:
        return None
    W, H, P = 720, 480, 70
    def span(m):
        lo = min(a[m]["mean"] - (a[m]["ci95"] or 0) for a in pts)
        hi = max(a[m]["mean"] + (a[m]["ci95"] or 0) for a in pts)
        pad = (hi - lo) * 0.1 or abs(hi) * 0.1 or 1
        return lo - pad, hi + pad
    (x0, x1), (y0, y1) = span(x), span(y)
    sx = lambda v: P + (v - x0) / (x1 - x0) * (W - 2 * P)
    sy = lambda v: H - P - (v - y0) / (y1 - y0) * (H - 2 * P)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" font-family="sans-serif" font-size="12">',
           f'<rect width="{W}" height="{H}" fill="white"/>',
           f'<line x1="{P}" y1="{H-P}" x2="{W-P}" y2="{H-P}" stroke="#333"/><line x1="{P}" y1="{P}" x2="{P}" y2="{H-P}" stroke="#333"/>',
           f'<text x="{W/2}" y="{H-25}" text-anchor="middle">{x} ({lab["objectives"][1]["direction"]})</text>',
           f'<text x="20" y="{H/2}" transform="rotate(-90 20 {H/2})" text-anchor="middle">{y} ({lab["objectives"][0]["direction"]})</text>']
    for v, f in ((x0, 0), (x1, 1)):
        out.append(f'<text x="{sx(v)}" y="{H-P+15}" text-anchor="middle">{v:.3g}</text>')
    for v in (y0, y1):
        out.append(f'<text x="{P-5}" y="{sy(v)+4}" text-anchor="end">{v:.3g}</text>')
    front = sorted([a for a in pts if a.get("status") == "frontier"], key=lambda a: a[x]["mean"])
    if len(front) > 1:
        out.append('<polyline fill="none" stroke="#29B5E8" stroke-width="2" points="' +
                   " ".join(f"{sx(a[x]['mean'])},{sy(a[y]['mean'])}" for a in front) + '"/>')
    for a in pts:
        cx, cy = sx(a[x]["mean"]), sy(a[y]["mean"])
        if a[x]["ci95"]:
            out.append(f'<line x1="{sx(a[x]["mean"]-a[x]["ci95"])}" y1="{cy}" x2="{sx(a[x]["mean"]+a[x]["ci95"])}" y2="{cy}" stroke="#999"/>')
        if a[y]["ci95"]:
            out.append(f'<line x1="{cx}" y1="{sy(a[y]["mean"]-a[y]["ci95"])}" x2="{cx}" y2="{sy(a[y]["mean"]+a[y]["ci95"])}" stroke="#999"/>')
        on = a.get("status") == "frontier"
        out.append(f'<circle cx="{cx}" cy="{cy}" r="6" fill="{"#29B5E8" if on else "#bbb"}" stroke="#333"/>')
        out.append(f'<text x="{cx+9}" y="{cy-8}">{a["alias"]}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main():
    lab = load_lab(sys.argv[1])
    runs_json = os.path.join(lab["_out"], "runs.json")
    if arg("--runs"):
        runs = arg("--runs").split(",")
    elif os.path.exists(runs_json):
        with open(runs_json) as f:
            runs = [r for r, st in json.load(f).items() if st in ("COMPLETED", "PARTIALLY_COMPLETED")]
    else:
        runs = [run_name(lab, v, k) for v in lab["variants"] for k in range(1, lab["repeats"] + 1)]
    # run -> short variant name; matches runs with or without an _r<k> suffix (and legacy <prefix>_<alias>_r<k>)
    known = {}
    for v in lab["variants"]:
        for key in {v["name"], v["alias"]}:
            known[key.lower()] = v["name"]
    alias_of = {}
    for r in runs:
        m = re.match(rf"^{re.escape(lab['run_prefix'])}_(.+?)(?:_r\d+)?$", r, re.IGNORECASE)
        key = m.group(1).lower() if m else r.lower()
        alias_of[r] = known.get(key, m.group(1) if m else r)
    for pair in (arg("--alias-map") or "").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            alias_of[k] = v

    conn = connect(lab)
    cur = conn.cursor()
    if "--no-views" not in sys.argv:
        whs = sorted({v["warehouse"] for v in lab["variants"] if v.get("warehouse")})
        sql = render_sql("sql/scorecard.sql.j2", v=view_prefix(lab), db=lab["_db"], schema=lab["_schema"],
                         name=lab["_name"], agent=lab["agent"], prefix=lab["run_prefix"], since=lab["since"],
                         runs=runs, run_list=", ".join(f"'{r}'" for r in runs),
                         threshold=float(lab["correct_threshold"]), warehouses=", ".join(f"'{w}'" for w in whs))
        os.makedirs(lab["_out"], exist_ok=True)
        with open(os.path.join(lab["_out"], "scorecard.sql"), "w") as f:
            f.write(sql)
        for c in conn.execute_stream(io.StringIO(sql), remove_comments=True):
            pass
        print(f"views {view_prefix(lab)}_* created for {len(runs)} runs")

    agg = frontier(lab, aggregate(lab, per_run_rows(lab, cur, runs), alias_of))
    with open(os.path.join(lab["_out"], "frontier.json"), "w") as f:
        json.dump(agg, f, indent=1, default=str)
    md = markdown(lab, agg)
    with open(os.path.join(lab["_out"], "frontier.md"), "w") as f:
        f.write(md)
    s = svg(lab, agg)
    if s:
        with open(os.path.join(lab["_out"], "frontier.svg"), "w") as f:
            f.write(s)
    print(md)


if __name__ == "__main__":
    main()
