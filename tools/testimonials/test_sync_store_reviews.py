#!/usr/bin/env python3
"""Regression tests for sync-store-reviews.py.

Standalone stdlib unittest (no pytest dependency) - this repo's gate commands
are Dart/website-only (see CLAUDE.md), so this script is not covered by any
existing CI harness. Run directly: `python3 tools/testimonials/test_sync_store_reviews.py`

Covers the 2026-09-05 incident: a review's real submission date getting
silently replaced by the sync moment (`now()`), and that value then being
stuck forever once already inserted (`ON CONFLICT ... DO NOTHING`). See
`.claude/skills/pre-release-diagnose/reports/` / feedback ID
2e2ff024-a7d6-49fc-b7e0-d22f986c2c34 for the field case (Ramy's 2026-05-24
Microsoft Store review, first synced with the wrong date on 2026-09-05).
"""
from __future__ import annotations

import importlib.util
import json
import os
import unittest
from unittest import mock

MODULE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sync-store-reviews.py")


def _load_module():
    spec = importlib.util.spec_from_file_location("sync_store_reviews", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ParseMsReviewDateTest(unittest.TestCase):
    def setUp(self):
        self.m = _load_module()

    def test_parses_real_submission_date(self):
        self.assertEqual(
            self.m.parse_ms_review_date("5/24/2026 1:14:46 AM"),
            "2026-05-24T01:14:46+00:00",
        )

    def test_returns_none_for_missing_or_unparseable_value(self):
        self.assertIsNone(self.m.parse_ms_review_date(None))
        self.assertIsNone(self.m.parse_ms_review_date(""))
        self.assertIsNone(self.m.parse_ms_review_date("not a date"))


class FetchMsReviewsDateGuardTest(unittest.TestCase):
    """A review with an unparseable/missing date must be skipped, never
    passed through with `received_at=None` (which upsert_reviews would
    otherwise silently stamp with `now()` - the exact 2026-09-05 incident)."""

    def setUp(self):
        self.m = _load_module()

    def test_skips_review_with_unparseable_date(self):
        fake_env = {
            "AZURE_TENANT_ID": "t",
            "AZURE_CLIENT_ID": "c",
            "AZURE_CLIENT_SECRET": "s",
            "WP_STORE_APP_ID": "app",
        }
        reviews_resp = (
            200,
            {
                "Value": [
                    {
                        "id": "good-1",
                        "rating": 1,
                        "reviewText": "fine",
                        "date": "5/24/2026 1:14:46 AM",
                    },
                    {
                        "id": "bad-1",
                        "rating": 1,
                        "reviewText": "bad date",
                        "date": "",
                    },
                ]
            },
        )

        class FakeUrlopenResponse:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps({"access_token": "fake-token"}).encode()

        with mock.patch.object(self.m, "load_env_file", return_value=fake_env):
            with mock.patch.object(self.m.urllib.request, "urlopen", return_value=FakeUrlopenResponse()):
                with mock.patch.object(self.m, "http", return_value=reviews_resp):
                    reviews = self.m.fetch_ms_reviews(min_rating=1, days=30)

        self.assertEqual([r["source_ref"] for r in reviews], ["good-1"])
        self.assertIsNotNone(reviews[0]["received_at"])


class UpsertReviewsConflictHandlingTest(unittest.TestCase):
    """Guards against silently re-perpetuating a bad `received_at`.

    Before the fix, `ON CONFLICT ... DO NOTHING` meant a row inserted once
    with a wrong date (e.g. from a pre-fix sync run, or a transient API
    hiccup) could never be corrected by a later, correct sync run. The
    upsert must instead update `received_at` on conflict.
    """

    def setUp(self):
        self.m = _load_module()

    def _run_upsert_and_capture_query(self, review):
        captured = {}

        def fake_http(method, url, headers=None, data=None):
            captured["query"] = data["query"]
            return 200, [{"inserted_count": 0, "corrected_count": 1}]

        with mock.patch.object(self.m, "load_env_file", return_value={"SUPABASE_ACCESS_TOKEN": "test-token"}):
            with mock.patch.object(self.m, "http", side_effect=fake_http):
                self.m.upsert_reviews([review], dry_run=False)

        return captured["query"]

    def test_conflict_clause_updates_received_at_instead_of_doing_nothing(self):
        review = {
            "rating": 1,
            "text": "It doesn't work.",
            "source": "microsoft_store",
            "source_ref": "1e832555-60fc-d2fd-5d07-5f62daff82c7",
            "received_at": "2026-05-24T01:14:46+00:00",
        }
        query = self._run_upsert_and_capture_query(review)

        self.assertNotIn("DO NOTHING", query)
        self.assertIn("DO UPDATE", query)
        self.assertIn("SET received_at = EXCLUDED.received_at", query)

    def test_conflict_update_is_guarded_against_null_received_at(self):
        # A row with no parseable date must never blank out an existing
        # correct received_at on a later re-sync.
        review = {
            "rating": 1,
            "text": "Some review",
            "source": "microsoft_store",
            "source_ref": "abc123",
            "received_at": None,
        }
        query = self._run_upsert_and_capture_query(review)

        self.assertIn("WHERE EXCLUDED.received_at IS NOT NULL", query)


if __name__ == "__main__":
    unittest.main()
