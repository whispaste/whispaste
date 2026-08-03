#!/usr/bin/env python3
"""Idempotently wraps AutoUpdaterMacosPlugin.register(...) in
GeneratedPluginRegistrant.swift with `#if !MAS_BUILD`/`#endif`.

Shared by two callers that need the same patch for different reasons:
  - macos/guard_mas_plugin_registrant.sh — Xcode build phase (MAS
    configuration only), the load-bearing reason this exists (see that
    script's header comment for the crash it prevents).
  - .githooks/pre-commit — self-heals the working-tree file before a
    commit, so `flutter pub get`/`flutter test`/`flutter analyze`
    regenerating this "Generated file. Do not edit." file (which drops the
    guard on every run) can never result in an unguarded version actually
    landing in git history.

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


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-GeneratedPluginRegistrant.swift>", file=sys.stderr)
        return 0

    path = sys.argv[1]
    try:
        with open(path) as f:
            content = f.read()
    except FileNotFoundError:
        print(f"warning: {path} not found — nothing to guard.", file=sys.stderr)
        return 0

    if "#if !MAS_BUILD" in content:
        print(f"{path} already guards AutoUpdaterMacosPlugin — nothing to do.")
        return 0

    new_content, n = PATTERN.subn(REPLACEMENT, content)
    if n == 0:
        print(
            "warning: AutoUpdaterMacosPlugin.register(...) line not found — "
            "Flutter's generated code may have changed shape.",
            file=sys.stderr,
        )
        return 0

    with open(path, "w") as f:
        f.write(new_content)
    print(f"patch_plugin_registrant_guard: guarded {n} occurrence(s) in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
