#!/usr/bin/env python3
"""Unit tests for render_manifest.py. Run: python3 packaging/buckets/test_render_manifest.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import render_manifest as rm  # noqa: E402

SCOOP = os.path.join(ROOT, "packaging/scoop/whispaste.json")
CASK = os.path.join(ROOT, "packaging/homebrew/whispaste.rb")
H1 = "a" * 64
H2 = "b" * 64


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


class Render(unittest.TestCase):
    def test_scoop_changes_only_version_url_hash(self):
        tpl = json.loads(read(SCOOP))
        out = json.loads(rm.render("scoop", read(SCOOP), "9.9.9", H1))
        self.assertEqual(out["version"], "9.9.9")
        arch = out["architecture"]["64bit"]
        self.assertEqual(arch["hash"], H1)
        self.assertEqual(
            arch["url"],
            "https://github.com/whispaste/whispaste/releases/download/v9.9.9/WhisPaste-9.9.9-windows-x64.zip",
        )
        for key in ("version", "architecture"):
            tpl.pop(key)
            out.pop(key)
        self.assertEqual(out, tpl)

    def test_cask_changes_only_version_and_sha(self):
        out = rm.render("homebrew", read(CASK), "9.9.9", H2)
        self.assertEqual(rm.fields("homebrew", out), ("9.9.9", H2))
        strip = lambda t: [l for l in t.splitlines() if not l.strip().startswith(("version ", "sha256 "))]  # noqa: E731
        self.assertEqual(strip(out), strip(read(CASK)))

    def test_rendering_the_current_file_with_its_own_fields_is_a_no_op(self):
        for kind, path in (("scoop", SCOOP), ("homebrew", CASK)):
            v, h = rm.fields(kind, read(path))
            self.assertEqual(rm.render(kind, read(path), v, h), read(path), kind)

    def test_refuses_bad_input(self):
        with self.assertRaises(rm.Refused):
            rm.render("scoop", read(SCOOP), "9.9.9-beta", H1)
        with self.assertRaises(rm.Refused):
            rm.render("scoop", read(SCOOP), "9.9.9", "deadbeef")
        with self.assertRaises(rm.Refused):
            rm.render("homebrew", 'cask "x" do\nend\n', "9.9.9", H1)


class Sums(unittest.TestCase):
    TEXT = f"# release v9.9.9 sha abc\n{H1}  WhisPaste-9.9.9-windows-x64.zip\n{H2}  WhisPaste-9.9.9-macos-arm64.zip\n"

    def test_lookup(self):
        self.assertEqual(rm.hash_from_sums(self.TEXT, "WhisPaste-9.9.9-macos-arm64.zip"), H2)

    def test_missing_or_ambiguous(self):
        with self.assertRaises(rm.Refused):
            rm.hash_from_sums(self.TEXT, "WhisPaste-9.9.8-windows-x64.zip")
        with self.assertRaises(rm.Refused):
            rm.hash_from_sums(self.TEXT + f"{H2}  WhisPaste-9.9.9-windows-x64.zip\n", "WhisPaste-9.9.9-windows-x64.zip")


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.asset = os.path.join(self.d, "WhisPaste-9.9.9-windows-x64.zip")
        with open(self.asset, "wb") as f:
            f.write(b"zip")
        self.sha = rm.sha256_file(self.asset)
        self.sums = os.path.join(self.d, "SHA256SUMS")
        with open(self.sums, "w") as f:
            f.write(f"# release v9.9.9 sha abc\n{self.sha}  WhisPaste-9.9.9-windows-x64.zip\n")
        self.out = os.path.join(self.d, "whispaste.json")

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, *args):
        return subprocess.run([sys.executable, "-I", os.path.join(HERE, "render_manifest.py"), *args],
                              capture_output=True, text=True)

    def render(self, *extra):
        return self.cli("render", "scoop", "--template", SCOOP, "--version", "9.9.9", "--out", self.out, *extra)

    def test_sums_and_asset_agree(self):
        r = self.render("--sums", self.sums, "--asset-file", self.asset)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.cli("fields", "scoop", self.out).stdout.split(), ["9.9.9", self.sha])

    def test_sums_and_asset_disagree(self):
        with open(self.asset, "ab") as f:
            f.write(b"tampered")
        r = self.render("--sums", self.sums, "--asset-file", self.asset)
        self.assertEqual(r.returncode, 1)
        self.assertIn("disagree", r.stderr)
        self.assertFalse(os.path.exists(self.out))

    def test_never_downgrades(self):
        newer = os.path.join(self.d, "current.json")
        with open(newer, "w", encoding="utf-8") as f:
            f.write(rm.render("scoop", read(SCOOP), "10.0.0", H1))
        r = self.render("--sums", self.sums, "--current", newer)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("kept", r.stdout)
        self.assertFalse(os.path.exists(self.out))

    def test_missing_current_is_fine(self):
        r = self.render("--sha256", self.sha, "--current", os.path.join(self.d, "absent.json"))
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_asset_names(self):
        self.assertEqual(self.cli("asset", "homebrew", "1.5.1").stdout.strip(), "WhisPaste-1.5.1-macos-arm64.zip")


if __name__ == "__main__":
    unittest.main()
