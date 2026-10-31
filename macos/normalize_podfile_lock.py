#!/usr/bin/env python3
"""Pins the `COCOAPODS: <version>` line of macos/Podfile.lock to the version
in macos/.cocoapods-version.

`pod install` writes the version of the CocoaPods that ran it into the last
line of Podfile.lock. That line says nothing about the app; with another
local CocoaPods it is the only change, and the file reads dirty for no
reason. Two callers:
  - scripts/sync-macos-plugins.sh, after its `pod install` (path argument);
  - the `podlock` git clean filter (see .gitattributes), so an implicit
    `pod install` from `flutter build macos` does not show as a change
    either (--stdin; git runs filters from the worktree root).

To move to a new CocoaPods on purpose, change macos/.cocoapods-version.
Exit code is always 0: without a pin file the content passes unchanged.
"""

import os
import re
import sys

PIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cocoapods-version")
LINE = re.compile(r"^COCOAPODS: .*$", re.MULTILINE)


def normalize(content: str) -> str:
    try:
        with open(PIN) as f:
            version = f.read().strip()
    except OSError:
        return content
    if not version:
        return content
    return LINE.sub(f"COCOAPODS: {version}", content)


def main() -> int:
    if sys.argv[1:] == ["--stdin"]:
        sys.stdout.write(normalize(sys.stdin.read()))
        return 0
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} (<Podfile.lock>|--stdin)", file=sys.stderr)
        return 0
    try:
        with open(sys.argv[1]) as f:
            content = f.read()
    except OSError:
        return 0
    new = normalize(content)
    if new != content:
        with open(sys.argv[1], "w") as f:
            f.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
