#!/usr/bin/env python3
"""Submits WhisPaste's editable Mac App Store version for App Review.

WHY THIS EXISTS
  Releases run fully unattended: `fastlane mac mas_release` uploads and
  attaches the build, then calls this script, which puts the version into
  review with release type AFTER_APPROVAL so Apple publishes it as soon as
  it is approved. No manual "Submit for Review" or "Release this version"
  click is part of the pipeline anymore.

  It uses the reviewSubmissions API rather than deliver's submit_for_review:
  deliver's build selection has attached stale builds before (see the
  Fastfile), and reviewSubmissions also picks up any in-app purchases that
  are already sitting in the platform's draft submission.

  In-app purchases themselves cannot be added through the API (Apple returns
  FIRST_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION, and reviewSubmissionItems
  has no IAP relationship). That only matters for a brand-new IAP; IAPs that
  were approved once need no resubmission.

USAGE
  python3 tools/appstore/submit-mas-review.py               # submit the editable version
  python3 tools/appstore/submit-mas-review.py --dry-run     # show what would be submitted

REQUIRES
  Same credentials as set-mac-price.py (~/.config/whispaste-ios-credentials/fastlane.env).
"""
import argparse
import importlib.util
import os
import sys
import time

_spec = importlib.util.spec_from_file_location(
    "set_mac_price", os.path.join(os.path.dirname(os.path.abspath(__file__)), "set-mac-price.py"))
asc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(asc)

PLATFORM = "MAC_OS"
EDITABLE_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}
IN_REVIEW_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW"}


def ok(status):
    return 200 <= status < 300


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def editable_version(token):
    s, r = asc.call(token, "GET", f"/v1/apps/{asc.APP_ID}/appStoreVersions"
                    f"?filter[platform]={PLATFORM}&include=build&limit=10")
    if not ok(s):
        fail(f"listing versions failed ({s}): {r}")
    for v in r.get("data", []):
        state = v["attributes"]["appStoreState"]
        if state in EDITABLE_STATES or state in IN_REVIEW_STATES:
            build = (v["relationships"].get("build", {}).get("data") or {}).get("id")
            return v, build
    fail("no editable Mac App Store version found")


def draft_submission(token, dry_run):
    s, r = asc.call(token, "GET", f"/v1/apps/{asc.APP_ID}/reviewSubmissions"
                    f"?filter[platform]={PLATFORM}&filter[state]=READY_FOR_REVIEW&limit=5")
    if not ok(s):
        fail(f"listing review submissions failed ({s}): {r}")
    if r.get("data"):
        return r["data"][0]["id"]
    if dry_run:
        return None
    s, r = asc.call(token, "POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions",
        "attributes": {"platform": PLATFORM},
        "relationships": {"app": {"data": {"type": "apps", "id": asc.APP_ID}}}}})
    if not ok(s):
        fail(f"creating review submission failed ({s}): {r}")
    return r["data"]["id"]


def submission_items(token, sub_id):
    s, r = asc.call(token, "GET", f"/v1/reviewSubmissions/{sub_id}/items"
                    "?include=appStoreVersion&fields[reviewSubmissionItems]=state,appStoreVersion&limit=50")
    if not ok(s):
        fail(f"listing submission items failed ({s}): {r}")
    return r.get("data", [])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token = asc.make_token(*asc.load_credentials())
    version, build_id = editable_version(token)
    vid = version["id"]
    attrs = version["attributes"]
    print(f"Version {attrs['versionString']} ({vid}): {attrs['appStoreState']}, "
          f"releaseType={attrs.get('releaseType')}, build={build_id}")
    if attrs["appStoreState"] in IN_REVIEW_STATES:
        print("Already in review — nothing to submit.")
        return
    if not build_id:
        fail("no build attached to the editable version (run mas_fix_build_attachment first)")

    if attrs.get("releaseType") != "AFTER_APPROVAL":
        if args.dry_run:
            print("Would set releaseType=AFTER_APPROVAL")
        else:
            s, r = asc.call(token, "PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
                "type": "appStoreVersions", "id": vid, "attributes": {"releaseType": "AFTER_APPROVAL"}}})
            if not ok(s):
                fail(f"setting releaseType failed ({s}): {r}")
            print("releaseType set to AFTER_APPROVAL")

    sub_id = draft_submission(token, args.dry_run)
    if args.dry_run:
        print(f"Would submit via review submission {sub_id or '<new>'}")
        return

    items = submission_items(token, sub_id)
    if not any((it["relationships"]["appStoreVersion"]["data"] or {}).get("id") == vid for it in items):
        s, r = asc.call(token, "POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        if not ok(s):
            fail(f"adding the version to the submission failed ({s}): {r}")
        items = submission_items(token, sub_id)
    print(f"Review submission {sub_id}: {len(items)} item(s)")

    s, r = asc.call(token, "PATCH", f"/v1/reviewSubmissions/{sub_id}", {"data": {
        "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    if not ok(s):
        fail(f"submitting failed ({s}): {r}")

    for _ in range(12):
        s, r = asc.call(token, "GET", f"/v1/reviewSubmissions/{sub_id}")
        state = r["data"]["attributes"]["state"] if ok(s) else None
        if state in ("WAITING_FOR_REVIEW", "IN_REVIEW"):
            print(f"Submitted: {state}, releases automatically after approval.")
            return
        time.sleep(5)
    fail(f"submission did not reach WAITING_FOR_REVIEW (last state: {state})")


if __name__ == "__main__":
    main()
