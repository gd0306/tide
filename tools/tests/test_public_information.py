import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.tests.test_ios_release import ROOT, synthetic_configuration


class PublicInformationTests(unittest.TestCase):
    def test_invalid_public_fields_leave_both_resources_untouched(self):
        paths = [
            ("publisher", "legalName"), ("publisher", "supportEmail"), ("links", "privacy"),
            ("appFilingNumber",), ("reviewed", "publicPages"), ("modelPolicy",), ("aiServices",),
            ("publisher",), ("links",), ("reviewed",), ("aiServices", 0),
            *(("aiServices", 0, field) for field in ("provider", "model", "baseURL", "filingNumber")),
        ]
        for path in paths:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                value = synthetic_configuration()
                target = value
                for key in path[:-1]:
                    target = target[key]
                target[path[-1]] = {"privateNote": "synthetic"}
                config = root / "input.json"
                config.write_text(json.dumps(value))
                ios = root / "mobile/ios/Application/PublicInformation.json"
                ios.parent.mkdir(parents=True)
                ios.write_text("original")
                result = subprocess.run([sys.executable, str(ROOT / "tools/generate_public_information.py"),
                                         "--config", str(config), "--output-root", temp], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(ios.read_text(), "original")
                self.assertFalse((root / "mobile/android").exists())

    def test_development_accepts_empty_public_strings_but_requires_concrete_service_identity(self):
        from tools.check_ios_release import public_information
        config = synthetic_configuration()
        config.update(modelPolicy="unrestricted", appFilingNumber="")
        config["publisher"] = {"legalName": "", "supportEmail": ""}
        config["reviewed"]["publicPages"] = False
        config["links"]["support"] = ""
        config["aiServices"][0]["filingNumber"] = ""
        self.assertEqual(public_information(config)["aiServices"][0]["filingNumber"], "")
        config["aiServices"][0]["model"] = ""
        with self.assertRaises(ValueError):
            public_information(config)

    def test_only_public_fields_are_generated_and_stale_output_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "release.json"
            value = synthetic_configuration()
            value["privateReviewNote"] = "private review material must not be bundled"
            config.write_text(json.dumps(value))
            command = [sys.executable, str(ROOT / "tools/generate_public_information.py"), "--config", str(config), "--output-root", str(root)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            ios = root / "mobile/ios/Application/PublicInformation.json"
            android = root / "mobile/android/app/src/main/res/raw/public_information.json"
            self.assertEqual(ios.read_bytes(), android.read_bytes())
            public = json.loads(ios.read_text())
            self.assertEqual(public["modelPolicy"], "declaredOnly")
            self.assertEqual(set(public["aiServices"][0]), {"provider", "model", "baseURL", "filingNumber"})
            self.assertEqual(public["publisherName"], "Synthetic Review Publisher")
            self.assertNotIn("authorizationReference", public["aiServices"][0])
            self.assertNotIn("privateReviewNote", public)
            self.assertEqual(subprocess.run(command + ["--check"], capture_output=True).returncode, 0)
            ios.write_text("{}")
            self.assertNotEqual(subprocess.run(command + ["--check"], capture_output=True).returncode, 0)
