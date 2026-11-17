import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.tests.test_ios_release import ROOT, synthetic_configuration


class PublicInformationTests(unittest.TestCase):
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
            self.assertEqual(public["publisherName"], "Synthetic Review Publisher")
            self.assertNotIn("authorizationReference", public["aiServices"][0])
            self.assertNotIn("privateReviewNote", public)
            self.assertEqual(subprocess.run(command + ["--check"], capture_output=True).returncode, 0)
            ios.write_text("{}")
            self.assertNotEqual(subprocess.run(command + ["--check"], capture_output=True).returncode, 0)
