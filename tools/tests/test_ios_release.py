"""Validate release input boundaries with synthetic, offline publisher information."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/check_ios_release.py"


def synthetic_configuration():
    return {
        "schemaVersion": 1,
        "bundleID": "cn.gd306.tideenglish.ios",
        "minimumOSVersion": "26.1",
        "regions": ["CN"],
        "publisher": {"legalName": "Synthetic Review Publisher", "supportEmail": "review@synthetic-tide-publisher.org"},
        "links": {key: "https://synthetic-tide-publisher.org/" + key for key in ("privacy", "support", "terms")},
        "appFilingNumber": "京ICP备2099000000号-1A",
        "aiServices": [{"provider": "Synthetic AI", "model": "synthetic-model", "filingNumber": "synthetic-filing-for-test-only", "authorizationReference": "https://synthetic-tide-publisher.org/agreement"}],
        "reviewed": {"privacy": True, "publicPages": True, "aiContentLabels": True, "providerAuthorization": True},
        "features": {"accounts": False, "hosted": False, "purchases": False},
    }


class IOSReleaseTests(unittest.TestCase):
    def run_check(self, config):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.json"
            path.write_text(json.dumps(config, ensure_ascii=False))
            return subprocess.run([sys.executable, str(SCRIPT), "--config", str(path)], cwd=ROOT, capture_output=True, text=True)

    def test_structurally_complete_configuration_reports_unverified_real_world_checks(self):
        result = self.run_check(synthetic_configuration())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report["ok"])
        self.assertIn("Government filing validity and provider authorization", report["notVerified"])

    def test_missing_publisher_and_filing_rejected(self):
        config = synthetic_configuration()
        config["publisher"]["legalName"] = ""
        config["appFilingNumber"] = ""
        result = self.run_check(config)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("publisher.legalName", result.stdout)
        self.assertIn("appFilingNumber", result.stdout)

    def test_placeholder_and_credential_bearing_urls_rejected(self):
        for url in ["https://tide-english.example/privacy/", "https://example.com/privacy", "https://privacy.test/", "http://synthetic-tide-publisher.org/privacy", "https://secret@synthetic-tide-publisher.org/privacy", "https://[::ffff:127.0.0.1]/privacy/", "https://device.local/privacy/"]:
            with self.subTest(url=url):
                config = synthetic_configuration()
                config["links"]["privacy"] = url
                self.assertNotEqual(self.run_check(config).returncode, 0)

    def test_unreviewed_ai_services_and_enabled_commerce_rejected(self):
        for mutate in [
            lambda c: c.update(aiServices=[]),
            lambda c: c["aiServices"][0].update(authorizationReference=""),
            lambda c: c["reviewed"].update(aiContentLabels=False),
            lambda c: c["features"].update(accounts=True),
            lambda c: c["features"].update(hosted=True),
            lambda c: c["features"].update(purchases=True),
        ]:
            config = copy.deepcopy(synthetic_configuration())
            mutate(config)
            self.assertNotEqual(self.run_check(config).returncode, 0)

    def test_different_bundle_or_regions_cannot_pass_this_release_profile(self):
        for key, value in [("bundleID", "com.synthetic.other"), ("regions", ["US"]), ("minimumOSVersion", "17.0")]:
            config = synthetic_configuration()
            config[key] = value
            self.assertNotEqual(self.run_check(config).returncode, 0)

    def test_malformed_config_returns_machine_readable_failure(self):
        result = self.run_check([])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)["ok"])
