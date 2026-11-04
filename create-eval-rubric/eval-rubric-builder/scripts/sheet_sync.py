"""Apply reviewer edits (CSV exported from the Google Sheet or edited candidate CSV).

  sheet_sync.py <dir> <edited.csv>   -> prints diff vs candidate_dataset.csv, writes dataset_v<N>.csv
Rows kept: reviewer_status in (approve, edit). 'edit' rows take the reviewer's values.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import read_csv, write_csv  # noqa: E402

KEEP = {"approve", "approved", "edit", "edited"}


def main(d: Path, edited: Path) -> None:
    base = {r["id"]: r for r in read_csv(d / "candidate_dataset.csv")}
    new = read_csv(edited)
    fields = list(new[0].keys()) if new else []
    kept, dropped, changed, added = [], [], [], []
    for r in new:
        st = (r.get("reviewer_status") or "").strip().lower()
        rid = r.get("id")
        if rid not in base:
            added.append(rid)
        else:
            diffs = [f for f in fields if f not in ("reviewer_status", "reviewer_notes")
                     and (r.get(f) or "") != (base[rid].get(f) or "")]
            if diffs:
                changed.append((rid, diffs))
        if st in KEEP:
            kept.append(r)
        else:
            dropped.append((rid, st or "blank"))
    missing = sorted(set(base) - {r.get("id") for r in new})
    print(f"kept {len(kept)} · dropped/unreviewed {len(dropped)} · edited {len(changed)} · new {len(added)}")
    for rid, diffs in changed:
        print(f"  ~ {rid}: {', '.join(diffs)}")
    for rid, st in dropped:
        print(f"  - {rid} ({st})")
    for rid in added:
        print(f"  + {rid}")
    if missing:
        print(f"  ! rows deleted in sheet (treated as dropped): {missing}")
    vs = [int(p.stem.split("_v")[1]) for p in d.glob("dataset_v*.csv")]
    out = d / f"dataset_v{max(vs, default=0) + 1}.csv"
    write_csv(out, kept, fields)
    print("wrote", out.name)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
