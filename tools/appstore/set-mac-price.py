#!/usr/bin/env python3
"""Sets WhisPaste's Mac App Store purchase price via the App Store Connect API.

WHY THIS EXISTS
  fastlane's `deliver`/Deliverfile has no working way to set an app's price:
  the `price_tier` action still exists but has been non-functional since
  Apple replaced price tiers with per-territory price points (2022/23) — see
  fastlane/fastlane#29841 (open, Jan 2026), #20442, #21370. There is no
  fastlane action for the App Store Connect API's `appPriceSchedules`
  resource either. This script talks to that API directly instead — it's the
  officially documented, if sparsely, path
  (developer.apple.com/documentation/appstoreconnectapi/app_metadata/pricing).

  Reuses the SAME credentials already provisioned for `fastlane mac
  mas_release` (see fastlane/load_credentials.rb) rather than the
  ~/.claude-global helper — this script must work from a bare checkout of
  this public repo without depending on the maintainer's personal machine
  layout.

USAGE
  python3 tools/appstore/set-mac-price.py --price 2.99                # DEU base territory, all others auto
  python3 tools/appstore/set-mac-price.py --price 2.99 --dry-run      # look up the price point, don't write
  python3 tools/appstore/set-mac-price.py --show                      # print the current price schedule

REQUIRES
  ~/.config/whispaste-ios-credentials/fastlane.env populated with
  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (same file `mas_release` uses).
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
BASE_TERRITORY = "DEU"
CREDENTIALS_FILE = os.path.expanduser("~/.config/whispaste-ios-credentials/fastlane.env")


def load_credentials():
    """Reads ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH the same way
    fastlane/load_credentials.rb does — same file, same format (KEY=value
    lines), so there is exactly one place that defines these values."""
    if not os.path.exists(CREDENTIALS_FILE):
        sys.exit(f"Missing credentials file: {CREDENTIALS_FILE} (see fastlane/load_credentials.rb)")
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


def find_price_point(token, target_price):
    """GET /v1/apps/{id}/appPricePoints filtered to the base territory, and
    return the entry whose customerPrice matches target_price (e.g. "2.99").
    Paginated — Apple's price point list runs into the hundreds of entries."""
    path = (
        f"/v1/apps/{APP_ID}/appPricePoints"
        f"?filter[territory]={BASE_TERRITORY}&limit=200"
    )
    while path:
        status, resp = call(token, "GET", path)
        if status != 200:
            sys.exit(f"GET appPricePoints failed: HTTP {status}\n{json.dumps(resp, indent=2)}")
        for point in resp.get("data", []):
            if point["attributes"].get("customerPrice") == target_price:
                return point["id"]
        next_link = resp.get("links", {}).get("next")
        if not next_link:
            break
        # `next` is a full URL; strip the API base to reuse call()'s path-based signature.
        path = next_link.replace(BASE, "")
    return None


def show_current_schedule(token):
    # `?include=manualPrices,baseTerritory` on /v1/apps/{id}/appPriceSchedule
    # itself 404s ("no resource of type 'null'") — verified 2026-07-28. The
    # working path (verified 2026-07-29): the schedule's `manualPrices`
    # relationship has its own `related` sub-resource endpoint
    # (/v1/appPriceSchedules/{scheduleId}/manualPrices), and THAT endpoint
    # accepts `?include=appPricePoint` — the included appPricePoints entry
    # carries the actual `customerPrice`/`proceeds` attributes. The
    # appPricePoint's own id (a base64 blob) canNOT be looked up directly via
    # /v1/appPricePoints/{id} or /v2/appPricePoints/{id} (both 404) — it only
    # resolves through this include.
    status, resp = call(token, "GET", f"/v1/apps/{APP_ID}/appPriceSchedule")
    print(f"HTTP {status}", file=sys.stderr)
    print(json.dumps(resp, indent=2, ensure_ascii=False))
    if status != 200:
        return

    schedule_id = resp["data"]["id"]
    status, prices_resp = call(
        token, "GET", f"/v1/appPriceSchedules/{schedule_id}/manualPrices?include=appPricePoint"
    )
    if status != 200:
        print(f"\nCould not resolve manual prices: HTTP {status}", file=sys.stderr)
        return
    points = {p["id"]: p["attributes"] for p in prices_resp.get("included", [])}
    print("\nManual prices:", file=sys.stderr)
    for price in prices_resp.get("data", []):
        point_id = price["relationships"]["appPricePoint"]["data"]["id"]
        attrs = points.get(point_id, {})
        print(
            f"  {attrs.get('customerPrice', '?')} EUR "
            f"(proceeds {attrs.get('proceeds', '?')} EUR, "
            f"startDate={price['attributes'].get('startDate')})",
            file=sys.stderr,
        )


def set_price(token, target_price, dry_run):
    price_point_id = find_price_point(token, target_price)
    if not price_point_id:
        sys.exit(
            f"No appPricePoint found for {target_price} EUR in territory {BASE_TERRITORY}. "
            "Apple's valid price points don't include every raw value — check "
            "https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability "
            "for the nearest tier and retry with that exact figure."
        )
    print(f"Found price point {price_point_id} for {target_price} EUR / {BASE_TERRITORY}", file=sys.stderr)

    if dry_run:
        print("--dry-run: not writing anything.", file=sys.stderr)
        return

    body = {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                "manualPrices": {
                    "data": [
                        {
                            "type": "appPrices",
                            "id": "${new-price}",
                        }
                    ]
                },
            },
        },
        "included": [
            {
                "type": "appPrices",
                "id": "${new-price}",
                "attributes": {"startDate": None},
                "relationships": {
                    "appPricePoint": {"data": {"type": "appPricePoints", "id": price_point_id}},
                },
            }
        ],
    }
    # Top-level collection, NOT nested under /v1/apps/{id}/ — verified live
    # 2026-07-28: the nested form 404s with "The relationship 'priceSchedules'
    # does not exist" (the app resource's relationship is the singular
    # `appPriceSchedule`, read-only; creation goes through the plural
    # top-level `appPriceSchedules` collection instead, with the target app
    # identified via the `app` relationship in the request body).
    status, resp = call(token, "POST", "/v1/appPriceSchedules", body)
    print(f"HTTP {status}", file=sys.stderr)
    print(json.dumps(resp, indent=2, ensure_ascii=False))
    if status not in (200, 201):
        sys.exit(1)
    print(f"\nPrice schedule submitted: {target_price} EUR base ({BASE_TERRITORY}), other territories automatic.", file=sys.stderr)
    print("Verify in App Store Connect → My Apps → WhisPaste → Pricing and Availability.", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--price", help='Target base-territory price, e.g. "2.99"')
    parser.add_argument("--dry-run", action="store_true", help="Look up the price point but don't write anything")
    parser.add_argument("--show", action="store_true", help="Print the current price schedule and exit")
    args = parser.parse_args()

    key_id, issuer_id, key_path = load_credentials()
    token = make_token(key_id, issuer_id, key_path)

    if args.show:
        show_current_schedule(token)
        return
    if not args.price:
        parser.error("--price is required unless --show is given")
    set_price(token, args.price, args.dry_run)


if __name__ == "__main__":
    main()
