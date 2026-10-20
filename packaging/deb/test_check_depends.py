#!/usr/bin/env python3
"""Unit tests for check_depends.py. Run: python3 packaging/deb/test_check_depends.py"""

import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import check_depends as cd  # noqa: E402

BASE = (
    "libgtk-3-0, libsecret-1-0, libnotify4, libayatana-appindicator3-1, "
    "libasound2, libcurl4, libkeybinder-3.0-0, libopusfile0, libogg0"
)


class ParseGroupsTest(unittest.TestCase):
    def test_alternatives_form_one_group(self):
        groups = cd.parse_groups("libflac14 | libflac12t64 | libflac8, libogg0")
        self.assertEqual(groups[0], frozenset({"libflac14", "libflac12t64", "libflac8"}))
        self.assertEqual(groups[1], frozenset({"libogg0"}))

    def test_version_constraints_are_ignored(self):
        groups = cd.parse_groups("libc6 (>= 2.34), libogg0 (>= 1.3)")
        self.assertEqual(groups, [frozenset({"libc6"}), frozenset({"libogg0"})])


class RequiredGroupsTest(unittest.TestCase):
    def check(self, value):
        return subprocess.run(
            [sys.executable, os.path.join(HERE, "check_depends.py"), "--field", value],
            capture_output=True, text=True,
        ).returncode

    def test_full_flac_group_passes(self):
        flac = "libflac14 | libflac12t64 | libflac12 | libflac8"
        self.assertEqual(self.check(f"{BASE}, {flac}"), 0)

    def test_single_flac_name_is_not_the_group(self):
        # Exact group match: one name alone must not satisfy the alternatives.
        for name in ("libflac14", "libflac12t64", "libflac12", "libflac8"):
            with self.subTest(name=name):
                self.assertEqual(self.check(f"{BASE}, {name}"), 1)

    def test_flac_group_missing_a_member_is_rejected(self):
        # Drops libflac12t64: the group no longer matches the required set.
        self.assertEqual(
            self.check(f"{BASE}, libflac14 | libflac12 | libflac8"), 1
        )

    def test_missing_ogg_is_rejected(self):
        self.assertEqual(self.check(BASE.replace(", libogg0", "") + ", libflac14"), 1)

    def test_template_passes(self):
        rc = subprocess.run(
            [sys.executable, os.path.join(HERE, "check_depends.py"),
             os.path.join(HERE, "control.template")],
            capture_output=True, text=True,
        ).returncode
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
