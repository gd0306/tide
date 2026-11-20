"""Exercise the public-brand guard against a real isolated Git file inventory."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.tests import test_project_identity as identity


class PublicSourceScanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / ".gitignore").write_text("distribution/private/\n")
        (self.root / "main.swift").write_text("Tide")
        subprocess.run(["git", "add", ".gitignore", "main.swift"], cwd=self.root, check=True)

    def scan(self):
        with patch.object(identity, "ROOT", self.root):
            identity.ProjectIdentityTests("test_no_previous_brand_in_source_paths_or_text").test_no_previous_brand_in_source_paths_or_text()

    def test_ignored_private_backup_does_not_fail_public_brand_guard(self):
        private = self.root / "distribution/private" / ("mu" + "ral")
        private.mkdir(parents=True)
        (private / "backup.txt").write_text("mu" + "ral")
        self.scan()

    def test_untracked_public_source_is_still_checked(self):
        (self.root / "new.swift").write_text("mu" + "ral")
        with self.assertRaises(AssertionError):
            self.scan()

    def test_tracked_source_cannot_be_hidden_by_later_ignore_rule(self):
        (self.root / "main.swift").write_text("mu" + "ral")
        (self.root / ".gitignore").write_text("distribution/private/\nmain.swift\n")
        with self.assertRaises(AssertionError):
            self.scan()
