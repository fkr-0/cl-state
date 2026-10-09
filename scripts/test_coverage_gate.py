"""Regression checks for the release coverage denominator and parser."""
import tempfile
import unittest
from pathlib import Path

from coverage_gate import measure


def html(rows):
    return "<table class='summary'>" + "".join(
        "<tr>" + "".join("<td>" + str(value) + "</td>" for value in row) + "</tr>"
        for row in rows) + "</table>"


class CoverageGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "src"
        self.source.mkdir()
        for name in ("packages.lisp", "core.lisp"):
            (self.source / name).write_text("", encoding="utf-8")
        self.index = root / "index.html"

    def test_excludes_only_package_declarations(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 9, 10, 90, 1, 2, 50)]), encoding="utf-8")
        result = measure(self.index, self.source)
        self.assertEqual(result["expressions"]["total"], 10)
        self.assertEqual(result["expressions"]["percent"], 90)
        self.assertEqual(result["branches"]["percent"], 50)

    def test_missing_source_fails_closed(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-")]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "missing source coverage"):
            measure(self.index, self.source)

    def test_impossible_counts_fail(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 11, 10, 110, 1, 2, 50)]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "invalid coverage counts"):
            measure(self.index, self.source)

    def test_duplicate_source_fails_closed(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 9, 10, 90, 1, 2, 50),
            ("core.lisp", 9, 10, 90, 1, 2, 50)]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            measure(self.index, self.source)


if __name__ == "__main__":
    unittest.main()
