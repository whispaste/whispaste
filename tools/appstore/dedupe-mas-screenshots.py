#!/usr/bin/env python3
"""Deterministically dedupes Mac App Store screenshots via the App Store
Connect API — a permanent fix for a recurring `deliver` race condition.

WHY THIS EXISTS
  `deliver`'s `overwrite_screenshots: true` deletes each locale's existing
  screenshots, then re-uploads from `fastlane/screenshots/`. Apple's delete
  is NOT immediately consistent: `deliver`'s own post-upload verification
  GET can still see the just-deleted screenshots as present (or as absent
  when they're actually still there), so it "fixes" the mismatch by
  re-uploading — producing two live copies with an IDENTICAL
  sourceFileChecksum. `overwrite_screenshots: true` does not prevent this;
  it is the trigger. Confirmed live at least three times (2026-07-29,
  2026-08-19/20, 2026-08-24 — see docs/store-release.md and the
  release-mac-app-store skill's "Duplikate-Falle").

  This script closes the loop deterministically instead of relying on a
  human to eyeball App Store Connect after every release: it lists what is
  actually there, group by checksum, and deletes every copy but one. Wired
  into `fastlane/Fastfile`'s `mas_release` lane as a mandatory step both
  BEFORE `upload_to_app_store` (clean baseline, in case a prior run left
  debris) and AFTER it (clean up whatever this run itself just produced) —
  see the `dedupe_mas_screenshots` lane there.

USAGE
  python3 tools/appstore/dedupe-mas-screenshots.py --show
  python3 tools/appstore/dedupe-mas-screenshots.py --dedupe
  python3 tools/appstore/dedupe-mas-screenshots.py --dedupe --expect 6   # fail loudly if the final count is still wrong

REQUIRES
  ~/.config/whispaste-ios-credentials/fastlane.env (ASC_KEY_ID, ASC_ISSUER_ID,
  ASC_KEY_PATH) — the same file `mas_release` and set-mac-price.py use.
  pip install pyjwt[crypto]
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

APP_ID = "6795319409"  # de.whispaste.app, App Store Connect
BASE = "https://api.appstoreconnect.apple.com"
CREDENTIALS_FILE = os.path.expanduser("~/.config/whispaste-ios-credentials/fastlane.env")
LOCALES = ("en-US", "de-DE")

# Editable-app-version states in which we're willing to touch screenshots.
# Deliberately excludes READY_FOR_SALE / post-submission states — this tool
# must never touch a version that's already live or in Apple's review queue.
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
}


def load_credentials():
    if not os.path.exists(CREDENTIALS_FILE):
        sys.exit(f"Missing credentials file: {CREDENTIALS_FILE}")
    env = {}
    with open(CREDENTIALS_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            env[key] = value
    for required in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
        if required not in env:
            sys.exit(f"{CREDENTIALS_FILE} is missing {required}")
    key_id = env["ASC_KEY_ID"]
    issuer_id = env["ASC_ISSUER_ID"]
    key_path = os.path.expanduser(
        env.get("ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    )
    if not os.path.exists(key_path):
        sys.exit(f"ASC private key not found: {key_path}")
    return key_id, issuer_id, key_path


def make_token(key_id, issuer_id, key_path):
    with open(key_path) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def call(token, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return r.status, (json.loads(text) if text else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            return e.code, json.loads(text)
        except ValueError:
            return e.code, text


def get_editable_version(token, allow_missing=False):
    status, resp = call(
        token, "GET", f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=MAC_OS&limit=10"
    )
    if status != 200:
        sys.exit(f"GET appStoreVersions failed: HTTP {status}\n{json.dumps(resp, indent=2)}")
    for v in resp["data"]:
        if v["attributes"]["appStoreState"] in EDITABLE_STATES:
            return v["id"], v["attributes"]["versionString"], v["attributes"]["appStoreState"]
    if allow_missing:
        return None, None, None
    sys.exit(
        "No editable macOS version found (none in "
        f"{sorted(EDITABLE_STATES)}) — refusing to touch screenshots on a "
        "non-editable (already submitted/live) version."
    )


def get_localizations(token, version_id):
    status, resp = call(
        token, "GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    )
    if status != 200:
        sys.exit(f"GET localizations failed: HTTP {status}\n{json.dumps(resp, indent=2)}")
    return {loc["attributes"]["locale"]: loc["id"] for loc in resp["data"] if loc["attributes"]["locale"] in LOCALES}


def get_screenshot_sets(token, loc_id):
    status, resp = call(token, "GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    if status != 200:
        sys.exit(f"GET screenshotSets failed: HTTP {status}\n{json.dumps(resp, indent=2)}")
    return resp["data"]


def get_screenshots(token, set_id):
    path = f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=200"
    out = []
    while path:
        status, resp = call(token, "GET", path)
        if status != 200:
            sys.exit(f"GET appScreenshots failed: HTTP {status}\n{json.dumps(resp, indent=2)}")
        out.extend(resp["data"])
        next_link = resp.get("links", {}).get("next")
        path = next_link.replace(BASE, "") if next_link else None
    return out


def dedupe_set(token, locale, display_type, set_id, dry_run):
    """Groups screenshots by sourceFileChecksum, keeps one COMPLETE copy per
    group, deletes the rest. Retries deletes a few times — a copy that is
    still ASSET_DELIVERY_STATE=UPLOAD_COMPLETE/processing can 409 on delete
    until Apple finishes processing it, which is exactly the same
    eventual-consistency lag that created the duplicate in the first place."""
    shots = get_screenshots(token, set_id)
    by_checksum = {}
    for sh in shots:
        checksum = sh["attributes"].get("sourceFileChecksum")
        by_checksum.setdefault(checksum, []).append(sh)

    print(f"  {locale}/{display_type}: {len(shots)} screenshots, {len(by_checksum)} distinct checksum(s)", file=sys.stderr)

    deleted_any = False
    for checksum, group in by_checksum.items():
        if len(group) <= 1:
            continue
        # Prefer keeping one whose asset delivery already reports COMPLETE;
        # falls back to the first entry if none do.
        group.sort(key=lambda sh: 0 if sh["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE" else 1)
        keep, drop = group[0], group[1:]
        print(f"    checksum={checksum}: keeping {keep['id']}, deleting {[d['id'] for d in drop]}", file=sys.stderr)
        if dry_run:
            continue
        for d in drop:
            for attempt in range(5):
                dstatus, dresp = call(token, "DELETE", f"/v1/appScreenshots/{d['id']}")
                if dstatus in (200, 204):
                    deleted_any = True
                    break
                if attempt == 4:
                    print(f"    FAILED to delete {d['id']}: HTTP {dstatus}\n{json.dumps(dresp, indent=2)}", file=sys.stderr)
                else:
                    time.sleep(3 * (attempt + 1))
    return deleted_any


def run(dedupe, expect, allow_missing_version=False):
    key_id, issuer_id, key_path = load_credentials()
    token = make_token(key_id, issuer_id, key_path)

    version_id, version_string, state = get_editable_version(token, allow_missing=allow_missing_version)
    if version_id is None:
        # No editable version yet (e.g. the previous version is READY_FOR_SALE
        # and `upload_to_app_store` hasn't created the next draft yet). A
        # version that doesn't exist yet has no screenshots to dedupe, so this
        # is a clean no-op — NOT the same thing as "found a version but it's
        # not editable", which stays a hard error above.
        print("No editable macOS version yet — nothing to dedupe (clean no-op).", file=sys.stderr)
        return True
    print(f"Version: {version_string} (id={version_id}, state={state})", file=sys.stderr)

    locs = get_localizations(token, version_id)
    ok = True
    for locale in LOCALES:
        loc_id = locs.get(locale)
        if not loc_id:
            continue
        for s in get_screenshot_sets(token, loc_id):
            display_type = s["attributes"]["screenshotDisplayType"]
            dedupe_set(token, locale, display_type, s["id"], dry_run=not dedupe)

    if expect is not None:
        # Re-fetch post-dedupe (or post-dry-run-inspection) counts and assert.
        for locale in LOCALES:
            loc_id = locs.get(locale)
            if not loc_id:
                continue
            for s in get_screenshot_sets(token, loc_id):
                display_type = s["attributes"]["screenshotDisplayType"]
                count = len(get_screenshots(token, s["id"]))
                status = "OK" if count == expect else "MISMATCH"
                print(f"  final: {locale}/{display_type} = {count} (expected {expect}) [{status}]", file=sys.stderr)
                if count != expect:
                    ok = False
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--show", action="store_true", help="List screenshots and planned dedup, without deleting")
    parser.add_argument("--dedupe", action="store_true", help="Actually delete excess duplicate screenshots")
    parser.add_argument("--expect", type=int, default=None, help="Fail (exit 1) if the final per-locale/set count isn't exactly this")
    parser.add_argument("--allow-missing-version", action="store_true", help="Treat 'no editable version yet' as a clean no-op instead of a hard error")
    args = parser.parse_args()
    if not args.show and not args.dedupe:
        parser.error("pass --show or --dedupe")

    ok = run(dedupe=args.dedupe, expect=args.expect, allow_missing_version=args.allow_missing_version)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
