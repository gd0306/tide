#!/usr/bin/env python3
"""Generate the same public release information for both native clients.

Drafts deliberately allow empty publisher fields. The separate release gate
requires complete reviewed information before a mainland App Store submission.
"""
import argparse
import json
from pathlib import Path
import sys

try:
    from tools.check_ios_release import public_information
except ModuleNotFoundError:
    from check_ios_release import public_information

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ["mobile/ios/Application/PublicInformation.json", "mobile/android/app/src/main/res/raw/public_information.json"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "distribution/ios/release-config.json")
    parser.add_argument("--output-root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        if not isinstance(config, dict) or config.get("schemaVersion") != 1:
            raise ValueError("Unsupported release configuration")
        encoded = (json.dumps(public_information(config), ensure_ascii=False, indent=2) + "\n").encode()
        stale = []
        for relative in OUTPUTS:
            path = args.output_root / relative
            if args.check:
                if not path.is_file() or path.read_bytes() != encoded:
                    stale.append(relative)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(encoded)
        if stale:
            print("Public information is out of date: " + ", ".join(stale), file=sys.stderr)
            return 1
    except (OSError, ValueError, TypeError, AttributeError, UnicodeError) as error:
        print("Public information could not be generated: " + type(error).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
