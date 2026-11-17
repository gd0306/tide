#!/usr/bin/env python3
"""Offline preparation gate for Tide's personal, mainland-China BYOK release.

Passing verifies the configuration's structure, never government approvals,
contracts, remote page contents or Apple signing. Debug builds do not run this gate.
"""
import argparse
import ipaddress
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
NOT_VERIFIED = [
    "Government filing validity and provider authorization",
    "Published privacy, support and terms page contents and availability",
    "App Store signing, review and regional service availability",
    "Real-device microphone, Bluetooth and live model behavior",
]


def public_https_url(value):
    if not isinstance(value, str) or value != value.strip() or any(c.isspace() for c in value):
        return False
    try:
        url = urlsplit(value)
        host = (url.hostname or "").lower().rstrip(".")
        _ = url.port
    except ValueError:
        return False
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        return False
    reserved = ("example.com", "example.net", "example.org", "localhost")
    return (url.scheme == "https" and "." in host and not url.username and not url.password
            and not url.fragment and host not in reserved
            and not host.endswith((".example", ".test", ".invalid", ".localhost", ".local"))
            and not any(host.endswith("." + item) for item in reserved)
            and not re.fullmatch(r"[\d.]+", host))


def validate(config):
    errors = []
    if not isinstance(config, dict):
        return ["configuration must be a JSON object"]

    def require(condition, field):
        if not condition:
            errors.append(field)

    def nonempty(value):
        return isinstance(value, str) and bool(value.strip()) and len(value) <= 500

    require(config.get("schemaVersion") == 1, "schemaVersion must be 1")
    require(config.get("bundleID") == "cn.gd306.tideenglish.ios", "bundleID must retain the Tide iOS identity")
    require(config.get("minimumOSVersion") == "26.1", "minimumOSVersion must match the application target (26.1)")
    require(config.get("regions") == ["CN"], "regions must contain only CN for this release profile")
    publisher = config.get("publisher") if isinstance(config.get("publisher"), dict) else {}
    require(nonempty(publisher.get("legalName")), "publisher.legalName is required")
    email = publisher.get("supportEmail")
    require(isinstance(email, str) and bool(re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email)), "publisher.supportEmail is required")
    links = config.get("links") if isinstance(config.get("links"), dict) else {}
    for key in ("privacy", "support", "terms"):
        require(public_https_url(links.get(key)), "links." + key + " must be a public HTTPS URL without placeholders or credentials")
    filing = config.get("appFilingNumber")
    require(isinstance(filing, str) and bool(re.fullmatch(r"[\u4e00-\u9fff]+ICP[备備]\d{6,20}号-\d+A", filing)), "appFilingNumber must be an APP filing number, not a website filing number")
    services = config.get("aiServices")
    require(isinstance(services, list) and 0 < len(services) <= 20, "aiServices must declare each enabled provider/model")
    if isinstance(services, list):
        for index, service in enumerate(services):
            if not isinstance(service, dict):
                errors.append(f"aiServices[{index}] must be an object")
                continue
            for field in ("provider", "model", "filingNumber"):
                require(nonempty(service.get(field)), f"aiServices[{index}].{field} is required")
            require(public_https_url(service.get("authorizationReference")), f"aiServices[{index}].authorizationReference must identify the usage agreement")
    reviewed = config.get("reviewed") if isinstance(config.get("reviewed"), dict) else {}
    for field in ("privacy", "publicPages", "aiContentLabels", "providerAuthorization"):
        require(reviewed.get(field) is True, "reviewed." + field + " must be confirmed before release")
    features = config.get("features") if isinstance(config.get("features"), dict) else {}
    for field in ("accounts", "hosted", "purchases"):
        require(features.get(field) is False, "features." + field + " must remain disabled for this BYOK release")
    return errors


def public_information(config):
    """Only intentionally public information goes into either application bundle."""
    publisher = config.get("publisher", {})
    return {
        "schemaVersion": 1,
        "publisherName": publisher.get("legalName", ""),
        "supportEmail": publisher.get("supportEmail", ""),
        "publicPagesReady": config.get("reviewed", {}).get("publicPages") is True,
        "links": {key: config.get("links", {}).get(key, "") for key in ("privacy", "support", "terms")},
        "appFilingNumber": config.get("appFilingNumber", ""),
        "aiServices": [{key: item.get(key, "") for key in ("provider", "model", "filingNumber")}
                       for item in config.get("aiServices", [])],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "distribution/ios/release-config.json")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        errors = validate(config)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        errors = ["Configuration could not be read: " + type(error).__name__]
    print(json.dumps({"ok": not errors, "errors": errors, "notVerified": NOT_VERIFIED}, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
