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

    def test_uninstrumented_runtime_file_fails_closed(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 0, 0, 0, 0, 0, "-")]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "zero source expression denominator"):
            measure(self.index, self.source)

    def test_duplicate_source_fails_closed(self):
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 9, 10, 90, 1, 2, 50),
            ("core.lisp", 9, 10, 90, 1, 2, 50)]), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            measure(self.index, self.source)

    def test_publishable_endpoint_requires_passing_gate(self):
        import json
        import subprocess
        import sys
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 8, 10, 80, 1, 2, 50)]), encoding="utf-8")
        output = self.index.parent / "output"
        script = Path(__file__).with_name("coverage_gate.py")
        cmd = [sys.executable, str(script), "--index", str(self.index),
               "--source", str(self.source), "--output", str(output),
               "--min", "85"]
        failed = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
        self.assertFalse((output / "endpoint.json").exists())
        self.assertEqual("80.00%", json.loads((output / "coverage-badge.json").read_text())["message"])

        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 9, 10, 90, 1, 2, 50)]), encoding="utf-8")
        passed = subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertEqual({"schemaVersion": 1, "label": "coverage",
                          "message": "90.00%", "color": "brightgreen"},
                         json.loads((output / "endpoint.json").read_text()))

        # A subsequent failing invocation must invalidate an earlier successful endpoint.
        self.index.write_text(html([
            ("packages.lisp", 0, 9, 0, 0, 0, "-"),
            ("core.lisp", 8, 10, 80, 1, 2, 50)]), encoding="utf-8")
        subprocess.run(cmd, capture_output=True, text=True, check=False)
        self.assertFalse((output / "endpoint.json").exists())


if __name__ == "__main__":
    unittest.main()
