#!/usr/bin/env python3
"""Idempotently wraps AutoUpdaterMacosPlugin.register(...) in
GeneratedPluginRegistrant.swift with `#if !MAS_BUILD`/`#endif`.

Shared by three callers that need the same patch for different reasons:
  - macos/guard_mas_plugin_registrant.sh — Xcode build phase (MAS
    configuration only), the load-bearing reason this exists (see that
    script's header comment for the crash it prevents).
  - .githooks/pre-commit — self-heals the working-tree file before a
    commit, so `flutter pub get`/`flutter test`/`flutter analyze`
    regenerating this "Generated file. Do not edit." file (which drops the
    guard on every run) can never result in an unguarded version actually
    landing in git history.
  - the `mas-guard` git clean filter (see .gitattributes) — normalizes the
    file for every `git status`/`git diff`/`git add`, not just at commit
    time. The build-phase and pre-commit healers only fix the file on disk
    at a *build* or a *commit*; in between (e.g. right after `flutter
    analyze`/`flutter test` silently regenerates it — routine, not a build
    or a commit), the working tree looked dirty for no actionable reason.
    A clean filter fixes that gap: git compares the *filtered* worktree
    content against the index, so an unguarded on-disk file still reads as
    unchanged without anyone having to build or commit first.

--stdin mode (used by the git filter) reads the file content from stdin and
writes the patched content to stdout — git filters pipe blobs, they don't
pass a file path. The original path-argument mode is unchanged for the
other two callers, which patch a real file in place.

Exit code is always 0 — a missing/differently-shaped file is reported but
never treated as fatal, matching both callers' existing tolerance for
Flutter changing the generated code's shape.
"""

import re
import sys

PATTERN = re.compile(
    r'(  AutoUpdaterMacosPlugin\.register\(with: registry\.registrar\('
    r'forPlugin: "AutoUpdaterMacosPlugin"\)\)\n)'
)
REPLACEMENT = '  #if !MAS_BUILD\n\\1  #endif\n'


def patch(content: str, label: str) -> tuple[str, bool]:
    """Returns (patched_content, changed). Never raises on shape mismatch."""
    if "#if !MAS_BUILD" in content:
        return content, False

    new_content, n = PATTERN.subn(REPLACEMENT, content)
    if n == 0:
        print(
            f"warning: AutoUpdaterMacosPlugin.register(...) line not found in {label} — "
            "Flutter's generated code may have changed shape.",
            file=sys.stderr,
        )
        return content, False

    return new_content, True


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--stdin":
        content = sys.stdin.read()
        new_content, _ = patch(content, "<stdin>")
        sys.stdout.write(new_content)
        return 0

    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} (<path-to-GeneratedPluginRegistrant.swift>|--stdin)", file=sys.stderr)
        return 0

    path = sys.argv[1]
    try:
        with open(path) as f:
            content = f.read()
    except FileNotFoundError:
        print(f"warning: {path} not found — nothing to guard.", file=sys.stderr)
        return 0

    new_content, changed = patch(content, path)
    if not changed:
        if "#if !MAS_BUILD" in content:
            print(f"{path} already guards AutoUpdaterMacosPlugin — nothing to do.")
        return 0

    with open(path, "w") as f:
        f.write(new_content)
    print(f"patch_plugin_registrant_guard: guarded {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
