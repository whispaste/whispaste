#!/usr/bin/env python3
"""Syncs Mac App Store + Microsoft Store customer reviews into the same
Supabase `user_feedback` table the in-app feedback form writes to, so the
website's testimonials section (Testimonials.astro -> public_testimonials
view) can draw from one central pool regardless of where a review came from.

WHY THIS EXISTS
  Store reviews are public, but the testimonials pipeline's contract is
  "anonymous, approved, rating >= 4" (see supabase/migrations/
  20260503093151_public_testimonials_view.sql and 20260826093316_curated_
  testimonial_text.sql). This script feeds that same pipeline instead of
  bypassing it: every row it inserts still needs a human to write
  curated_text and flip approved_for_display = true (via the Supabase
  Table Editor) before it shows up on the site — see supabase/migrations/
  20260831_add_feedback_source_tracking.sql. No reviewer name or country is
  ever fetched or stored — only rating + review text, matching the exact
  anonymity contract the in-app feedback rows already have.

  Only rating >= --min-rating reviews are fetched at all (default 4) — this
  script is a testimonials feed, not a review-monitoring tool (that's
  .claude/skills/pre-release-diagnose, which already watches for new
  low-rating reviews separately).

AUTH
  Mac App Store:   ~/.config/whispaste-ios-credentials/fastlane.env
                    (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) — same file
                    `fastlane mac mas_release` and tools/appstore/
                    set-mac-price.py already use.
  Microsoft Store:  ~/.config/microsoft-partnercenter/.env
                    (AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET,
                    WP_STORE_APP_ID) — same file .claude/skills/
                    pre-release-diagnose/scripts/fetch-store-health.sh uses.
  Supabase:         repo-root .env, SUPABASE_ACCESS_TOKEN. Writes go through
                    the Supabase Management API's SQL endpoint (the same
                    access path the Supabase MCP server uses), not the
                    anon/PostgREST path — the anon INSERT policy requires
                    device_id_hash/app_version/category and is deliberately
                    scoped to the in-app feedback form only.

USAGE
  python3 tools/testimonials/sync-store-reviews.py                 # both stores, rating >= 4
  python3 tools/testimonials/sync-store-reviews.py --dry-run       # fetch + show, don't write
  python3 tools/testimonials/sync-store-reviews.py --ms-days 720   # wider MS Store lookback (first backfill)
  python3 tools/testimonials/sync-store-reviews.py --min-rating 5  # only 5-star reviews

REQUIRES
  pip install pyjwt[crypto] requests
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ASC_CREDENTIALS_FILE = os.path.expanduser("~/.config/whispaste-ios-credentials/fastlane.env")
MS_CREDENTIALS_FILE = os.path.expanduser("~/.config/microsoft-partnercenter/.env")
SUPABASE_ENV_FILE = os.path.join(REPO_ROOT, ".env")

ASC_BASE = "https://api.appstoreconnect.apple.com"
ASC_APP_ID = "6795319409"  # de.whispaste.app — same id as tools/appstore/set-mac-price.py

SUPABASE_PROJECT_REF = "cnyniyflnefxrwafuqig"  # same ref as website/src/components/Testimonials.astro


def load_env_file(path):
    if not os.path.exists(path):
        return {}
    env = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            env[key.strip()] = value.strip()
    return env


def http(method, url, headers=None, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req_headers = {"User-Agent": "whispaste-sync-store-reviews/1.0"}
    req_headers.update(headers or {})
    if body is not None:
        req_headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, method=method, headers=req_headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            text = r.read().decode()
            return r.status, (json.loads(text) if text else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            return e.code, json.loads(text)
        except ValueError:
            return e.code, text


# ─── Mac App Store (App Store Connect API) ──────────────────────────────────

def fetch_mas_reviews(min_rating, max_pages=5):
    env = load_env_file(ASC_CREDENTIALS_FILE)
    for required in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
        if required not in env:
            print(f"[mas] skipping — {ASC_CREDENTIALS_FILE} missing {required}", file=sys.stderr)
            return []
    key_id = env["ASC_KEY_ID"]
    issuer_id = env["ASC_ISSUER_ID"]
    key_path = os.path.expanduser(env.get("ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"))
    if not os.path.exists(key_path):
        print(f"[mas] skipping — private key not found: {key_path}", file=sys.stderr)
        return []

    with open(key_path) as f:
        private_key = f.read()
    now = int(time.time())
    token = jwt.encode(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )
    headers = {"Authorization": f"Bearer {token}"}

    reviews = []
    path = f"/v1/apps/{ASC_APP_ID}/customerReviews?sort=-createdDate&limit=200"
    pages = 0
    while path and pages < max_pages:
        status, resp = http("GET", ASC_BASE + path, headers=headers)
        if status != 200:
            print(f"[mas] GET customerReviews failed: HTTP {status}\n{resp}", file=sys.stderr)
            break
        for item in resp.get("data", []):
            attrs = item.get("attributes", {})
            rating = attrs.get("rating")
            if rating is None or rating < min_rating:
                continue
            title = (attrs.get("title") or "").strip()
            body = (attrs.get("body") or "").strip()
            text = f"{title} {body}".strip() if title and title != body else (body or title)
            if not text:
                continue
            created_date = attrs.get("createdDate")
            if not created_date:
                # See the matching guard in fetch_ms_reviews: never let a
                # missing date fall through to upsert_reviews' `now()`
                # fallback and get mislabeled as "just received".
                print(f"[mas] skipping review {item['id']} — missing createdDate", file=sys.stderr)
                continue
            reviews.append(
                {
                    "rating": rating,
                    "text": text,
                    "source": "mas",
                    "source_ref": item["id"],
                    # ISO 8601 already, e.g. "2026-08-25T12:00:00-07:00" -
                    # Postgres timestamptz parses it as-is.
                    "received_at": created_date,
                }
            )
        pages += 1
        next_link = resp.get("links", {}).get("next")
        path = next_link.replace(ASC_BASE, "") if next_link else None

    print(f"[mas] fetched {len(reviews)} review(s) with rating >= {min_rating}", file=sys.stderr)
    return reviews


# ─── Microsoft Store (Partner Center Analytics API) ─────────────────────────

def parse_ms_review_date(value):
    """Parse the reviews endpoint's "date" field (e.g. "8/23/2026 1:32:43 PM",
    UTC) into an ISO 8601 string Postgres can store as timestamptz."""
    if not value:
        return None
    try:
        parsed = datetime.datetime.strptime(value, "%m/%d/%Y %I:%M:%S %p")
    except ValueError:
        return None
    return parsed.replace(tzinfo=datetime.timezone.utc).isoformat()


def fetch_ms_reviews(min_rating, days):
    env = load_env_file(MS_CREDENTIALS_FILE)
    required = ("AZURE_TENANT_ID", "AZURE_CLIENT_ID", "AZURE_CLIENT_SECRET", "WP_STORE_APP_ID")
    missing = [v for v in required if v not in env]
    if missing:
        print(f"[ms] skipping — {MS_CREDENTIALS_FILE} missing {', '.join(missing)}", file=sys.stderr)
        return []

    token_body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": env["AZURE_CLIENT_ID"],
            "client_secret": env["AZURE_CLIENT_SECRET"],
            "resource": "https://manage.devcenter.microsoft.com",
        }
    ).encode()
    req = urllib.request.Request(
        f"https://login.microsoftonline.com/{env['AZURE_TENANT_ID']}/oauth2/token",
        data=token_body,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            token_resp = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        print(f"[ms] skipping — token request failed: HTTP {e.code}", file=sys.stderr)
        return []
    access_token = token_resp.get("access_token")
    if not access_token:
        print("[ms] skipping — no access_token in response", file=sys.stderr)
        return []

    end_date = time.strftime("%m/%d/%Y", time.gmtime())
    start_date = time.strftime("%m/%d/%Y", time.gmtime(time.time() - days * 86400))
    url = (
        "https://manage.devcenter.microsoft.com/v1.0/my/analytics/reviews"
        f"?applicationId={env['WP_STORE_APP_ID']}&startDate={start_date}&endDate={end_date}&top=500"
    )
    status, resp = http("GET", url, headers={"Authorization": f"Bearer {access_token}"})
    if status != 200:
        print(f"[ms] reviews query failed: HTTP {status}\n{resp}", file=sys.stderr)
        return []

    reviews = []
    for item in (resp or {}).get("Value", []):
        rating = item.get("rating")
        title = (item.get("reviewTitle") or "").strip()
        body = (item.get("reviewText") or "").strip()
        text = f"{title} {body}".strip() if title and title != body else (body or title)
        if rating is None or rating < min_rating or not text:
            continue
        ref = item.get("id")
        if not ref:
            # Fallback for any response shape without a stable id.
            ref = hashlib.sha256(f"{item.get('date', '')}|{text}".encode()).hexdigest()
        received_at = parse_ms_review_date(item.get("date"))
        if received_at is None:
            # Never let an unparseable/missing date fall through to
            # upsert_reviews' `now()` fallback: that fallback is meant for
            # sources that genuinely have no submission date, not for a
            # transient API/parsing hiccup silently mislabeling a review as
            # "just received" (2026-09-05 incident, feedback ID
            # 2e2ff024-a7d6-49fc-b7e0-d22f986c2c34 — see also the
            # ON CONFLICT DO UPDATE fix in upsert_reviews below).
            print(
                f"[ms] skipping review {ref} — unparseable date {item.get('date')!r}",
                file=sys.stderr,
            )
            continue
        reviews.append(
            {
                "rating": rating,
                "text": text,
                "source": "microsoft_store",
                "source_ref": ref,
                "received_at": received_at,
            }
        )

    print(f"[ms] fetched {len(reviews)} review(s) with rating >= {min_rating}", file=sys.stderr)
    return reviews


# ─── Supabase write (Management API, bypasses PostgREST/RLS) ───────────────

def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def upsert_reviews(reviews, dry_run):
    if not reviews:
        print("Nothing to insert.")
        return

    if dry_run:
        print(f"[dry-run] would upsert {len(reviews)} review(s):")
        for r in reviews:
            preview = r["text"][:80] + ("…" if len(r["text"]) > 80 else "")
            print(f"  {r['rating']}★ [{r['source']}] {preview}")
        return

    env = load_env_file(SUPABASE_ENV_FILE)
    access_token = env.get("SUPABASE_ACCESS_TOKEN")
    if not access_token:
        sys.exit(f"Missing SUPABASE_ACCESS_TOKEN in {SUPABASE_ENV_FILE}")

    values_sql = ",\n".join(
        f"({r['rating']}, {sql_literal(r['text'])}, {sql_literal(r['source'])}, {sql_literal(r['source_ref'])}, "
        f"{sql_literal(r['received_at']) + '::timestamptz' if r.get('received_at') else 'now()'})"
        for r in reviews
    )
    # ON CONFLICT DO UPDATE (received_at only) rather than DO NOTHING: an
    # already-synced row must still pick up a corrected received_at if a
    # earlier bug (or a store API quirk) inserted it with the wrong date -
    # otherwise every future re-sync silently perpetuates the bad value
    # forever. Only received_at is touched; curated_text/approved_for_display
    # (human-curated) and status (triage state) are never overwritten here.
    query = f"""
        WITH upserted AS (
            INSERT INTO public.user_feedback (rating, feedback_text, source, source_ref, received_at)
            SELECT rating, feedback_text, source, source_ref, received_at
            FROM (VALUES
                {values_sql}
            ) AS v(rating, feedback_text, source, source_ref, received_at)
            ON CONFLICT (source, source_ref) WHERE source_ref IS NOT NULL DO UPDATE
                SET received_at = EXCLUDED.received_at
                WHERE EXCLUDED.received_at IS NOT NULL
                    AND user_feedback.received_at IS DISTINCT FROM EXCLUDED.received_at
            RETURNING id, (xmax = 0) AS was_insert
        )
        SELECT
            count(*) FILTER (WHERE was_insert) AS inserted_count,
            count(*) FILTER (WHERE NOT was_insert) AS corrected_count
        FROM upserted;
    """

    status, resp = http(
        "POST",
        f"https://api.supabase.com/v1/projects/{SUPABASE_PROJECT_REF}/database/query",
        headers={"Authorization": f"Bearer {access_token}"},
        data={"query": query},
    )
    if status not in (200, 201):
        sys.exit(f"Supabase write failed: HTTP {status}\n{resp}")

    inserted_count = resp[0]["inserted_count"] if resp else 0
    corrected_count = resp[0]["corrected_count"] if resp else 0
    skipped = len(reviews) - int(inserted_count) - int(corrected_count)
    print(
        f"Inserted {inserted_count} new review(s), corrected {corrected_count} "
        f"already-synced received_at value(s), skipped {skipped} unchanged duplicate(s)."
    )
    if int(inserted_count) > 0:
        print(
            "New rows land as approved_for_display = false (enforced server-side). "
            "Curate + approve them in the Supabase Table Editor (user_feedback table: "
            "write curated_text, set approved_for_display = true) before they appear "
            "on the website."
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--min-rating", type=int, default=4)
    parser.add_argument("--ms-days", type=int, default=365, help="Microsoft Store review lookback window in days")
    parser.add_argument("--dry-run", action="store_true", help="Fetch and print, don't write to Supabase")
    parser.add_argument("--skip-mas", action="store_true")
    parser.add_argument("--skip-ms", action="store_true")
    args = parser.parse_args()

    reviews = []
    if not args.skip_mas:
        reviews += fetch_mas_reviews(args.min_rating)
    if not args.skip_ms:
        reviews += fetch_ms_reviews(args.min_rating, args.ms_days)

    upsert_reviews(reviews, args.dry_run)


if __name__ == "__main__":
    main()
