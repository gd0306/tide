import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class IOSRuntimeSelectionTests(unittest.TestCase):
    def load(self):
        path = ROOT / "tools/run_ios_checks.py"
        spec = importlib.util.spec_from_file_location("tide_ios_checks", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_chooses_newest_available_ios_runtime_that_can_run_the_app(self):
        runtimes = [
            {"identifier": "ios-26", "version": "26.0", "isAvailable": True, "name": "iOS 26.0"},
            {"identifier": "ios-27", "version": "27.0", "isAvailable": False, "name": "iOS 27.0"},
            {"identifier": "watch-27", "version": "27.0", "isAvailable": True, "name": "watchOS 27.0"},
            {"identifier": "ios-26-4", "version": "26.4", "isAvailable": True, "name": "iOS 26.4"},
            {"identifier": "ios-26-1", "version": "26.1", "isAvailable": True, "name": "iOS 26.1"},
        ]
        self.assertEqual(self.load().select_runtime(runtimes), "ios-26-4")

    def test_no_suitable_runtime_fails_instead_of_using_an_older_system(self):
        with self.assertRaises(RuntimeError):
            self.load().select_runtime([{"identifier": "ios-26", "version": "26.0", "isAvailable": True, "name": "iOS 26.0"}])
