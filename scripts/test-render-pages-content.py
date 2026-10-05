#!/usr/bin/env python3
"""Exercise the Pages renderer through its build entry point."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


class PagesBuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for directory in ("docs/site", "journal", "metadata/transactions"):
            shutil.copytree(ROOT / directory, self.root / directory)
        reports = self.root / "docs/reports"
        reports.mkdir()
        monthly = (ROOT / "docs/reports/2026-09-report.md").read_text()
        (reports / "2026-09-report.md").write_text(monthly)
        # Both reports end on the same date; quarterly must win.
        self.quarterly = reports / "2026-Q3-report.md"
        self.quarterly.write_text(monthly.replace("September 2026", "Q3 2026"))
        (self.root / "scripts").mkdir()
        for name in ("build-pages.sh", "render-pages-content.py"):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)

    def build(self):
        return subprocess.run(
            ["bash", str(self.root / "scripts/build-pages.sh")],
            text=True, capture_output=True,
        )

    def assert_build_fails(self, diagnostic):
        result = self.build()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(diagnostic, result.stderr)
        self.assertFalse((self.root / "_site/.nojekyll").exists())

    def test_quarterly_status_is_rendered(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        page = (self.root / "_site/index.html").read_text()
        self.assertIn('Based on <a href="https://github.com/blinklabs-io/treasury-proposal/blob/main/docs/reports/2026-Q3-report.md">', page)
        self.assertIn("Q3 2026 — In progress", page)
        self.assertIn("Q2 2026: Complete", page)
        self.assertLess(page.index("Q3 2026 — In progress"), page.index("Q2 2026 — Complete"))
        self.assertIn('<span class="status-scope">Operational hardening and storage scalability</span>', page)
        self.assertIn('<span class="status-note">Storage and parity validation advanced; audit engagement is not recorded as started.</span>', page)
        self.assertNotIn("<!-- GENERATED_", page)

    def test_latest_report_without_milestones_fails(self):
        self.quarterly.write_text(self.quarterly.read_text().replace("## Milestones", "## Other"))
        self.assert_build_fails("milestone")

    def test_missing_and_duplicate_quarters_fail(self):
        for replacement in ("Q5 2026:", "Q2 2026:"):
            with self.subTest(replacement=replacement):
                original = self.quarterly.read_text()
                self.quarterly.write_text(original.replace("Q3 2026:", replacement))
                self.assert_build_fails("expected exactly one milestone")
                self.quarterly.write_text(original)

    def test_unknown_status_fails(self):
        self.quarterly.write_text(self.quarterly.read_text().replace("| In progress |", "| Update |"))
        self.assert_build_fails("status")

    def test_missing_roadmap_placeholder_fails(self):
        template = self.root / "docs/site/index.html"
        template.write_text(template.read_text().replace("<!-- GENERATED_Q3_2026_STATUS -->", "stale status"))
        self.assert_build_fails("GENERATED_Q3_2026_STATUS")

    def test_no_reports_fails(self):
        for report in self.quarterly.parent.glob("*.md"):
            report.unlink()
        self.assert_build_fails("report")

    def test_incomplete_latest_report_is_not_skipped(self):
        self.quarterly.write_text(self.quarterly.read_text().replace("## Summary", "## Other"))
        self.assert_build_fails("Summary")

    def test_missing_funding_metadata_fails(self):
        for metadata in (self.root / "metadata/transactions").glob("*.json"):
            metadata.unlink()
        self.assert_build_fails("funding")


if __name__ == "__main__":
    unittest.main()
