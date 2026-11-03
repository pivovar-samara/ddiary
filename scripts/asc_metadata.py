#!/usr/bin/env python3
"""Upload promotional text and release notes ("What's New") to App Store Connect.

Texts live in docs/app-store/<version>/<locale>/{promotional_text,release_notes}.txt,
where <locale> is an App Store Connect locale code (en-US, ru, de-DE, ...).

Dry run by default: prints what is in App Store Connect now and what would change.
Pass --apply to actually write.

Auth (App Store Connect API key, role App Manager or Admin):
  ASC_KEY_ID       key ID
  ASC_ISSUER_ID    issuer ID
  ASC_KEY_PATH     path to AuthKey_<KEY_ID>.p8
                   (default ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8)

Usage:
  scripts/asc_metadata.py 1.3                     # dry run, all locales in the folder
  scripts/asc_metadata.py 1.3 --locales en-US,ru  # dry run, selected locales
  scripts/asc_metadata.py 1.3 --locales en-US,ru --apply
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.pivovar.DDiary"
ROOT = Path(__file__).resolve().parent.parent
TEXTS_DIR = ROOT / "docs" / "app-store"
PROMO_LIMIT = 170
NOTES_LIMIT = 4000
# States in which "What's New" can still be edited. Promotional text is editable in any state.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "INVALID_BINARY", "WAITING_FOR_REVIEW",
}


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw_signature(der: bytes) -> bytes:
    """openssl emits ECDSA signatures as DER SEQUENCE{r, s}; JWT ES256 wants r||s, 32 bytes each."""
    def read_int(buf, i):
        assert buf[i] == 0x02
        length = buf[i + 1]
        value = buf[i + 2:i + 2 + length].lstrip(b"\x00")
        return value.rjust(32, b"\x00"), i + 2 + length

    assert der[0] == 0x30
    i = 3 if der[1] & 0x80 else 2
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r + s


def make_token() -> str:
    key_id = os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        sys.exit("Set ASC_KEY_ID and ASC_ISSUER_ID (and ASC_KEY_PATH if the key is elsewhere).")
    key_path = Path(os.environ.get(
        "ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")).expanduser()
    if not key_path.is_file():
        sys.exit(f"API key not found: {key_path}")

    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=signing_input.encode(), capture_output=True, check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_to_raw_signature(der))}"


class Client:
    """Signs a fresh token before the current one runs out, so long runs (uploads, polling) keep working."""

    def __init__(self):
        self.token, self.issued = make_token(), time.time()

    def request(self, method: str, path: str, params=None, body=None):
        if time.time() - self.issued > 10 * 60:
            self.token, self.issued = make_token(), time.time()
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, method=method, headers={
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            sys.exit(f"{method} {path} -> HTTP {e.code}\n{detail}")

    def get(self, path, **params):
        return self.request("GET", path, params)


def load_texts(version: str, locales):
    version_dir = TEXTS_DIR / version
    if not version_dir.is_dir():
        sys.exit(f"No texts folder: {version_dir}")
    # screenshots/ sits next to the locale folders but is handled by asc_screenshots.py.
    available = sorted(p.name for p in version_dir.iterdir() if p.is_dir() and p.name != "screenshots")
    selected = locales or available
    texts, errors = {}, []
    for locale in selected:
        d = version_dir / locale
        if not d.is_dir():
            errors.append(f"{locale}: folder {d} is missing")
            continue
        entry = {}
        promo, notes = d / "promotional_text.txt", d / "release_notes.txt"
        if promo.is_file():
            entry["promotionalText"] = promo.read_text().strip()
            if len(entry["promotionalText"]) > PROMO_LIMIT:
                errors.append(f"{locale}: promotional text is {len(entry['promotionalText'])} chars (max {PROMO_LIMIT})")
        if notes.is_file():
            entry["whatsNew"] = notes.read_text().strip()
            if len(entry["whatsNew"]) > NOTES_LIMIT:
                errors.append(f"{locale}: release notes are {len(entry['whatsNew'])} chars (max {NOTES_LIMIT})")
        if not entry:
            errors.append(f"{locale}: no promotional_text.txt or release_notes.txt")
        texts[locale] = entry
    if errors:
        sys.exit("\n".join(errors))
    return texts


def show(label, value):
    print(f"  {label}:")
    for line in (value or "<empty>").splitlines():
        print(f"    | {line}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", help="App Store version string, e.g. 1.3")
    parser.add_argument("--locales", help="Comma-separated ASC locale codes; default: every folder under the version")
    parser.add_argument("--apply", action="store_true", help="Write to App Store Connect (default is a dry run)")
    parser.add_argument("--create-missing", action="store_true",
                        help="Add a version localization for locales the version does not have yet")
    args = parser.parse_args()

    texts = load_texts(args.version, args.locales.split(",") if args.locales else None)
    api = Client()

    apps = api.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID} visible to this API key.")
    app_id = apps[0]["id"]

    versions = api.get(f"/v1/apps/{app_id}/appStoreVersions", **{
        "filter[versionString]": args.version, "filter[platform]": "IOS"})["data"]
    if not versions:
        sys.exit(f"Version {args.version} does not exist in App Store Connect yet. Create it there first.")
    version = versions[0]
    state = version["attributes"].get("appStoreState") or version["attributes"].get("appVersionState")
    print(f"App {app_id}, version {args.version} ({version['id']}), state {state}")
    notes_editable = state in EDITABLE_STATES
    if not notes_editable:
        print(f"  ! Release notes cannot be changed in state {state}; only promotional text will be sent.")

    existing = {
        loc["attributes"]["locale"]: loc
        for loc in api.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                           limit=200)["data"]
    }
    print(f"Locales on the version: {', '.join(sorted(existing)) or 'none'}\n")

    plan = []
    for locale, new in texts.items():
        if not notes_editable:
            new = {k: v for k, v in new.items() if k != "whatsNew"}
        current = existing.get(locale)
        old = current["attributes"] if current else {}
        changes = {k: v for k, v in new.items() if (old.get(k) or "").strip() != v}
        print(f"[{locale}]" + ("" if current else "  (not on the version yet)"))
        if not changes:
            print("  no changes\n")
            continue
        for key in changes:
            label = "Promotional text" if key == "promotionalText" else "Release notes"
            show(f"{label} — now", old.get(key))
            show(f"{label} — new", changes[key])
        print()
        if current is None and not args.create_missing:
            print("  ! skipped: pass --create-missing to add this locale to the version\n")
            continue
        plan.append((locale, current, changes))

    if not args.apply:
        print(f"Dry run: {len(plan)} locale(s) would be updated. Re-run with --apply to send.")
        return

    for locale, current, changes in plan:
        if current:
            api.request("PATCH", f"/v1/appStoreVersionLocalizations/{current['id']}", body={"data": {
                "type": "appStoreVersionLocalizations", "id": current["id"], "attributes": changes}})
        else:
            api.request("POST", "/v1/appStoreVersionLocalizations", body={"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale, **changes},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
            }})
        print(f"[{locale}] updated: {', '.join(changes)}")
    print("Done.")


if __name__ == "__main__":
    main()
