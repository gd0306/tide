#!/usr/bin/env python3
"""Build and test offline UI flows on a newly created, isolated iPhone simulator."""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TESTS = [
    "testCompactTranslationKeepsVocabularyVisibleAndPreservesDraftWhenCollapsed",
    "testChineseInterfaceAtLargestTextSizeKeepsControlsReachable",
    "testVocabularyPageWorkDoesNotBlockNavigation",
]


def select_runtime(runtimes):
    candidates = []
    for runtime in runtimes:
        if not runtime.get("isAvailable") or not runtime.get("name", "").startswith("iOS "):
            continue
        try:
            version = tuple(int(part) for part in runtime["version"].split("."))
        except (KeyError, ValueError):
            continue
        if version >= (26, 1):
            candidates.append((version, runtime["identifier"]))
    if not candidates:
        raise RuntimeError("Install an available iOS Simulator runtime >= 26.1 before running Tide UI checks.")
    return max(candidates)[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", action="append", dest="tests", help="XCTest method name; repeat to select multiple offline cases")
    parser.add_argument("--derived-data", type=Path, default=ROOT / ".build/ios-ci")
    parser.add_argument("--packages", type=Path, default=ROOT / ".build/ios-ci-packages")
    parser.add_argument("--results", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("These checks require an Apple Silicon macOS runner.")
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "--json"]))["runtimes"]
    runtime = select_runtime(runtimes)
    run_id = uuid.uuid4().hex[:12]
    simulator = subprocess.check_output([
        "xcrun", "simctl", "create", "Tide-CI-" + run_id,
        "com.apple.CoreSimulator.SimDeviceType.iPhone-17", runtime,
    ], text=True).strip()
    results = args.results or ROOT / (".build/ios-ui-" + run_id + ".xcresult")
    try:
        subprocess.run(["xcrun", "simctl", "boot", simulator], check=True)
        command = [
            "xcodebuild", "-project", "mobile/ios/TideEnglish.xcodeproj", "-scheme", "TideEnglish",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={simulator},arch=arm64",
            "-derivedDataPath", str(args.derived_data), "-clonedSourcePackagesDirPath", str(args.packages),
            "-resultBundlePath", str(results), "-parallel-testing-enabled", "NO",
            "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
        ]
        for name in args.tests or DEFAULT_TESTS:
            if not name.startswith("test") or not name.isidentifier():
                raise ValueError("Select an XCTest method name, not a shell command or a live verification flag.")
            command.append("-only-testing:TideEnglishUITests/TideEnglishUITests/" + name)
        subprocess.run(command + ["test"], cwd=ROOT, check=True)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], check=False, capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", simulator], check=True)
    print("Tide offline UI checks passed; results: " + str(results))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
