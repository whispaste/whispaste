#!/usr/bin/env python3
"""Scoop and Homebrew manifest of one WhisPaste release, rendered from the packaging template.

One implementation for both places that write these manifests:
  - scripts/release/manifests.sh on the Mac (hash from the local artifact),
  - the workflow update-manifest.yml in whispaste/scoop-bucket and whispaste/homebrew-tap,
    which runs a copy of this file as .github/scripts/render_manifest.py (hash from the
    published SHA256SUMS, cross-checked against the downloaded asset).
Only version, download URL and hash change; everything else comes from the template.

  render_manifest.py asset  <scoop|homebrew> <version>
  render_manifest.py fields <scoop|homebrew> <manifest>      -> "<version> <sha256>"
  render_manifest.py render <scoop|homebrew> --template T --version V --out O
                            (--sha256 H | --asset-file F | --sums S [--asset-file F])
                            [--current C]
--current names the manifest that is published now: when it already carries a newer version,
nothing is written (a late or repeated run never downgrades the bucket).
Tests: python3 packaging/buckets/test_render_manifest.py
"""
import argparse
import hashlib
import json
import re
import sys

REPO = "whispaste/whispaste"
ASSETS = {
    "scoop": "WhisPaste-{v}-windows-x64.zip",
    "homebrew": "WhisPaste-{v}-macos-arm64.zip",
}
STABLE = re.compile(r"^\d+\.\d+\.\d+$")
SHA = re.compile(r"^[0-9a-f]{64}$")
CASK_VERSION = re.compile(r'version "([^"]*)"')
CASK_SHA = re.compile(r'sha256 "([^"]*)"')


class Refused(Exception):
    pass


def asset_name(kind, version):
    return ASSETS[kind].format(v=version)


def base_url(version):
    return f"https://github.com/{REPO}/releases/download/v{version}"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def hash_from_sums(text, name):
    """Hash of `name` in a shasum -a 256 listing (the release's SHA256SUMS, '#' header allowed)."""
    found = set()
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].strip().lstrip("*") == name:
            found.add(parts[0].lower())
    if not found:
        raise Refused(f"{name} is not listed in SHA256SUMS")
    if len(found) > 1:
        raise Refused(f"{name} is listed with different hashes in SHA256SUMS")
    return found.pop()


def version_tuple(version):
    return tuple(int(p) for p in version.split("."))


def fields(kind, text):
    if kind == "scoop":
        data = json.loads(text)
        return data["version"], data["architecture"]["64bit"]["hash"].lower()
    v, s = CASK_VERSION.search(text), CASK_SHA.search(text)
    if not v or not s:
        raise Refused("cask without version or sha256 line")
    return v.group(1), s.group(1).lower()


def render(kind, template, version, sha):
    if not STABLE.match(version):
        raise Refused(f"{version} is no stable version")
    if not SHA.match(sha):
        raise Refused(f"{sha!r} is no sha256")
    if kind == "scoop":
        data = json.loads(template)
        data["version"] = version
        arch = data["architecture"]["64bit"]
        arch["url"] = f"{base_url(version)}/{asset_name(kind, version)}"
        arch["hash"] = sha
        return json.dumps(data, indent=4, ensure_ascii=False) + "\n"
    text, n_version = CASK_VERSION.subn(f'version "{version}"', template, count=1)
    text, n_sha = CASK_SHA.subn(f'sha256 "{sha}"', text, count=1)
    if n_version != 1 or n_sha != 1:
        raise Refused("cask template without version or sha256 line")
    return text


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def cmd_render(args):
    version = args.version
    asset = asset_name(args.kind, version)
    candidates = []
    if args.sha256:
        candidates.append(("--sha256", args.sha256.lower()))
    if args.sums:
        candidates.append(("SHA256SUMS", hash_from_sums(read(args.sums), asset)))
    if args.asset_file:
        candidates.append((asset, sha256_file(args.asset_file)))
    if not candidates:
        raise Refused("no hash source: pass --sha256, --asset-file or --sums")
    if len({h for _, h in candidates}) != 1:
        raise Refused("hash sources disagree: " + ", ".join(f"{s} {h[:16]}" for s, h in candidates))
    sha = candidates[0][1]
    if args.current:
        try:
            current = fields(args.kind, read(args.current))[0]
        except FileNotFoundError:
            current = None
        if current and STABLE.match(current) and version_tuple(current) > version_tuple(version):
            print(f"{args.kind}: kept, {args.current} already has the newer {current}")
            return
    out = render(args.kind, read(args.template), version, sha)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"{args.kind}: {version}, sha256 {sha[:16]}...")


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("asset")
    a.add_argument("kind", choices=ASSETS)
    a.add_argument("version")
    f = sub.add_parser("fields")
    f.add_argument("kind", choices=ASSETS)
    f.add_argument("manifest")
    r = sub.add_parser("render")
    r.add_argument("kind", choices=ASSETS)
    r.add_argument("--template", required=True)
    r.add_argument("--version", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--sha256")
    r.add_argument("--asset-file")
    r.add_argument("--sums")
    r.add_argument("--current")
    args = p.parse_args(argv)
    try:
        if args.cmd == "asset":
            print(asset_name(args.kind, args.version))
        elif args.cmd == "fields":
            print(*fields(args.kind, read(args.manifest)))
        else:
            cmd_render(args)
    except (Refused, KeyError, ValueError, OSError) as e:
        print(f"render_manifest: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
