import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.tests.test_ios_release import ROOT, synthetic_configuration


class PublicPagesTests(unittest.TestCase):
    def test_builds_three_pages_without_private_release_notes_or_html_injection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "release.json"
            value = synthetic_configuration()
            value["publisher"]["legalName"] = "Synthetic <Publisher>"
            value["privateNote"] = "private material must not be public"
            config.write_text(json.dumps(value))
            result = subprocess.run([sys.executable, str(ROOT / "tools/build_public_pages.py"), "--config", str(config), "--output", str(root / "site")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in ("privacy", "support", "terms"):
                text = (root / "site" / name / "index.html").read_text()
                self.assertIn("Synthetic &lt;Publisher&gt;", text)
                self.assertNotIn("private material", text)
                self.assertIn('lang="zh-CN"', text)

    def test_incomplete_config_requires_explicit_draft_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = [sys.executable, str(ROOT / "tools/build_public_pages.py"), "--output", str(root / "site")]
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertFalse((root / "site/privacy/index.html").exists())
            self.assertEqual(subprocess.run(command + ["--draft"], capture_output=True).returncode, 0)
            self.assertIn('name="robots" content="noindex"', (root / "site/privacy/index.html").read_text())
