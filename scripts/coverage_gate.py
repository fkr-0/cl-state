#!/usr/bin/env python3
"""Enforce SB-COVER expression coverage with an audited source denominator.

Includes every src/state/*.lisp file except packages.lisp, which contains
declarations, not executable library behavior. Branch metrics are reported
but expression coverage is the release gate.
"""
import argparse
import json
from html.parser import HTMLParser
from pathlib import Path


class Rows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.row = []
        if tag == "td" and self.row is not None:
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag == "td" and self.cell is not None:
            self.row.append("".join(self.cell).strip())
            self.cell = None
        if tag == "tr" and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def measure(index: Path, source: Path):
    expected = {p.name for p in source.glob("*.lisp")}
    if "packages.lisp" not in expected or len(expected) < 2:
        raise ValueError("invalid source inventory")
    parser = Rows()
    parser.feed(index.read_text(encoding="utf-8"))
    files = {}
    for row in parser.rows:
        if len(row) != 7 or not row[0].endswith(".lisp"):
            continue
        name = row[0]
        if name not in expected or name in files:
            raise ValueError(f"unexpected or duplicate coverage entry: {name}")
        e, n, b, m = (int(row[i]) for i in (1, 2, 4, 5))
        if not (0 <= e <= n and 0 <= b <= m):
            raise ValueError(f"invalid coverage counts: {name}")
        # A listed runtime file with no executable expressions is not evidence
        # that SB-COVER instrumented it. Fail rather than shrink the denominator.
        if name != "packages.lisp" and n == 0:
            raise ValueError(f"zero source expression denominator: {name}")
        files[name] = {"expression_covered": e, "expression_total": n,
                       "branch_covered": b, "branch_total": m}
    if set(files) != expected:
        raise ValueError(f"missing source coverage: {sorted(expected - set(files))}")
    filtered = {k: v for k, v in files.items() if k != "packages.lisp"}
    e = sum(v["expression_covered"] for v in filtered.values())
    n = sum(v["expression_total"] for v in filtered.values())
    b = sum(v["branch_covered"] for v in filtered.values())
    m = sum(v["branch_total"] for v in filtered.values())
    if n == 0:
        raise ValueError("zero expression denominator")
    return {"metric": "SB-COVER instrumented expressions",
            "source": "src/state/*.lisp",
            "excluded": {"packages.lisp": "package declarations only"},
            "expressions": {"covered": e, "total": n, "percent": round(100 * e / n, 4)},
            "branches": {"covered": b, "total": m,
                         "percent": round(100 * b / m, 4) if m else None},
            "files": filtered}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--index", type=Path, default=Path("coverage/cover-index.html"))
    p.add_argument("--source", type=Path, default=Path("src/state"))
    p.add_argument("--output", type=Path, default=Path("coverage"))
    p.add_argument("--min", type=float, required=True)
    a = p.parse_args()
    if not 0 <= a.min <= 100:
        p.error("--min must be between 0 and 100")
    # Never publish a cached endpoint after an invalid or failing measurement.
    endpoint = a.output / "endpoint.json"
    endpoint.unlink(missing_ok=True)
    report = measure(a.index, a.source)
    a.output.mkdir(parents=True, exist_ok=True)
    (a.output / "coverage.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    pc = report["expressions"]["percent"]
    passed = report["expressions"]["covered"] * 100 >= a.min * report["expressions"]["total"]
    badge = {"schemaVersion": 1, "label": "coverage",
             "message": f"{pc:.2f}%", "color": "brightgreen" if passed else "red"}
    (a.output / "coverage-badge.json").write_text(json.dumps(badge, sort_keys=True) + "\n")
    if passed:
        verified = dict(badge, color="brightgreen" if pc >= 90 else "green")
        endpoint.write_text(json.dumps(verified, sort_keys=True) + "\n")
    print(f"Coverage: {report['expressions']['covered']}/{report['expressions']['total']} "
          f"= {pc:.2f}%; required {a.min:.2f}%. Excluded: packages.lisp only.")
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
