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
        "modelPolicy": "declaredOnly",
        "aiServices": [{"provider": "openAI", "baseURL": "https://api.openai.com/v1", "model": "synthetic-model", "filingNumber": "synthetic-filing-for-test-only", "authorizationReference": "https://synthetic-tide-publisher.org/agreement"}],
        "reviewed": {"privacy": True, "publicPages": True, "aiContentLabels": True, "providerAuthorization": True},
        "features": {"accounts": False, "hosted": False, "purchases": False},
    }


class IOSReleaseTests(unittest.TestCase):
    def run_check(self, config):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "release.json"
            path.write_text(json.dumps(config, ensure_ascii=False))
            return subprocess.run([sys.executable, str(SCRIPT), "--config", str(path)], cwd=ROOT, capture_output=True, text=True)

    def test_shared_native_declarations_and_public_urls(self):
        from tools.check_ios_release import public_https_url, validate
        fixture = json.loads((ROOT / "packages/fixtures/cross-platform/release-model-policy.json").read_text())
        config = synthetic_configuration()
        agreement = config["aiServices"][0]["authorizationReference"]
        config["aiServices"] = [dict(entry, authorizationReference=agreement) for entry in fixture["metadata"]["aiServices"]]
        self.assertEqual(validate(config), [])
        for entry in fixture["invalidDeclarations"]:
            with self.subTest(entry=entry):
                self.assertTrue(validate(dict(config, aiServices=[dict(entry, authorizationReference=agreement)])))
        for value in fixture["validURLs"]:
            self.assertTrue(public_https_url(value), value)
        for value in fixture["invalidURLs"]:
            self.assertFalse(public_https_url(value), value)

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
        for url in ["https://bad..site/privacy", "https://bad\\host.cn/privacy", "https://@gd306.cn/tide/privacy/", "https://bad-.site/", "https://bad.site/%zz", "https://bad.site/\x01route", "https://tide-english.example/privacy/", "https://example.com/privacy", "https://privacy.test/", "http://synthetic-tide-publisher.org/privacy", "https://secret@synthetic-tide-publisher.org/privacy", "https://[::ffff:127.0.0.1]/privacy/", "https://device.local/privacy/"]:
            with self.subTest(url=url):
                config = synthetic_configuration()
                config["links"]["privacy"] = url
                self.assertNotEqual(self.run_check(config).returncode, 0)

    def test_unreviewed_ai_services_and_enabled_commerce_rejected(self):
        for mutate in [
            lambda c: c.update(aiServices=[]),
            lambda c: c.pop("modelPolicy"),
            lambda c: c.update(modelPolicy="unrestricted"),
            lambda c: c["aiServices"][0].update(provider="alien"),
            lambda c: c["aiServices"][0].update(model="*"),
            lambda c: c["aiServices"][0].update(baseURL="https://wrong.org"),
            lambda c: c["aiServices"][0].update(provider="custom", baseURL=""),
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
