#!/usr/bin/env python3
"""Offline preparation gate for Tide's personal, mainland-China BYOK release.

Passing verifies the configuration's structure, never government approvals,
contracts, remote page contents or Apple signing. Debug builds do not run this gate.
"""
import argparse
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


# Use the same unambiguous ASCII URL grammar as both native readers.
PUBLIC_URL = re.compile(r"https://([A-Za-z0-9.-]+)(?::([0-9]{1,5}))?((?:/[A-Za-z0-9._~!$&'()*+,;=:@/%-]*)?(?:\?[A-Za-z0-9._~!$&'()*+,;=:@/?%-]*)?)")
DNS_LABEL = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
RESERVED = ("example.com", "example.net", "example.org", "example", "test", "invalid", "localhost", "local", "internal", "home.arpa", "onion", "alt", "localdomain", "home", "corp", "lan")
BASE_URLS = {
    "openAI": "https://api.openai.com/v1", "deepSeek": "https://api.deepseek.com",
    "glm": "https://open.bigmodel.cn/api/paas/v4",
    "gemini": "https://generativelanguage.googleapis.com/v1beta/openai", "custom": None,
}
APP_FILING = re.compile(r"[\u4e00-\u9fff]+ICP[备備]\d{6,20}号-\d+A")


def support_email(value):
    if not isinstance(value, str) or len(value) > 254:
        return False
    local, at, domain = value.partition("@")
    return (at == "@" and 0 < len(local) <= 64 and not local.startswith(".")
            and not local.endswith(".") and ".." not in local
            and re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+", local) is not None
            and re.fullmatch(r"[a-zA-Z0-9.-]+", domain) is not None
            and public_https_url("https://" + domain))


def public_https_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        return False
    match = PUBLIC_URL.fullmatch(value)
    if not match:
        return False
    host, port, suffix = match.groups()
    host = host.lower()
    labels = host.split(".")
    return (len(host) <= 253 and len(labels) > 1 and all(DNS_LABEL.fullmatch(label) for label in labels)
            and labels[-1][0].isalpha()
            and not any(host == name or host.endswith("." + name) for name in RESERVED)
            and (port is None or 1 <= int(port) <= 65535)
            and not re.search(r"%(?![0-9a-fA-F]{2})|%(?:0[0-9A-Fa-f]|1[0-9A-Fa-f]|7[Ff]|5[Cc])", suffix))


def validate(config):
    errors = []
    if not isinstance(config, dict):
        return ["configuration must be a JSON object"]

    def require(condition, field):
        if not condition:
            errors.append(field)

    def nonempty(value):
        return isinstance(value, str) and bool(value.strip()) and len(value) <= 500

    try:
        public_information(config)
    except ValueError as error:
        errors.append(str(error))
    require(config.get("modelPolicy") == "declaredOnly", "modelPolicy must be declaredOnly for formal release")
    require(config.get("schemaVersion") == 1, "schemaVersion must be 1")
    require(config.get("bundleID") == "cn.gd306.tideenglish.ios", "bundleID must retain the Tide iOS identity")
    require(config.get("minimumOSVersion") == "26.1", "minimumOSVersion must match the application target (26.1)")
    require(config.get("regions") == ["CN"], "regions must contain only CN for this release profile")
    publisher = config.get("publisher") if isinstance(config.get("publisher"), dict) else {}
    require(nonempty(publisher.get("legalName")), "publisher.legalName is required")
    email = publisher.get("supportEmail")
    require(support_email(email), "publisher.supportEmail is required")
    links = config.get("links") if isinstance(config.get("links"), dict) else {}
    for key in ("privacy", "support", "terms"):
        require(public_https_url(links.get(key)), "links." + key + " must be a public HTTPS URL without placeholders or credentials")
    filing = config.get("appFilingNumber")
    require(isinstance(filing, str) and bool(APP_FILING.fullmatch(filing)), "appFilingNumber must be an APP filing number, not a website filing number")
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
    def require(condition, name):
        if not condition:
            raise ValueError("Invalid public field: " + name)

    def string(obj, name, accepts=lambda _: True, allow_empty=True):
        value = obj.get(name)
        require(isinstance(value, str) and len(value) <= 2048 and value == value.strip()
                and all(character.isprintable() for character in value)
                and ((allow_empty and value == "") or (value and accepts(value))), name)
        return value

    require(isinstance(config, dict) and type(config.get("schemaVersion")) is int
            and config["schemaVersion"] == 1, "schemaVersion")
    for key in ("publisher", "links", "reviewed"):
        require(isinstance(config.get(key), dict), key)
    ready = config["reviewed"].get("publicPages")
    require(type(ready) is bool, "reviewed.publicPages")
    mode = string(config, "modelPolicy", lambda v: v in ("unrestricted", "declaredOnly"), False)
    services = config.get("aiServices")
    require(isinstance(services, list) and len(services) <= 20, "aiServices")
    public_services = []
    for item in services:
        require(isinstance(item, dict), "aiServices entry")
        provider = string(item, "provider", lambda v: v in BASE_URLS, False)
        model = string(item, "model", lambda v: re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}", v), False)
        base = string(item, "baseURL", public_https_url, False)
        parsed = urlsplit(base)
        require(not any(c in base for c in "%?#") and "//" not in parsed.path and
                all(part not in (".", "..") for part in parsed.path.split("/")), "baseURL")
        port = "" if parsed.port in (None, 443) else ":" + str(parsed.port)
        canonical = "https://" + parsed.hostname + port + parsed.path.rstrip("/")
        gemini_live = provider == "gemini" and model == "models/gemini-3.8-live"
        expected = "https://generativelanguage.googleapis.com" if gemini_live else BASE_URLS[provider]
        require(base == canonical and (provider == "custom" or expected == base), "baseURL")
        public_services.append(dict(provider=provider, model=model, baseURL=base,
                                    filingNumber=string(item, "filingNumber", lambda v: len(v) <= 500, mode == "unrestricted")))
    return {
        "schemaVersion": 1,
        "publisherName": string(config["publisher"], "legalName", lambda v: len(v) <= 500),
        "supportEmail": string(config["publisher"], "supportEmail", support_email),
        "publicPagesReady": ready,
        "links": {key: string(config["links"], key, public_https_url, not ready) for key in ("privacy", "support", "terms")},
        "appFilingNumber": string(config, "appFilingNumber", APP_FILING.fullmatch),
        "modelPolicy": mode,
        "aiServices": public_services,
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
