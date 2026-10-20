#!/usr/bin/env python3
"""Checks a Debian Depends field against the required runtime groups.

Usage:
  check_depends.py <control.template>     read the Depends field from a template
  check_depends.py --field "<Depends>"    check a Depends value given directly
  dpkg-deb -f pkg.deb Depends | check_depends.py -   read the value from stdin

Each comma-separated entry is one group of `|` alternatives. A required group
must appear exactly as written (same alternatives, nothing missing), so a
library that only offers one name (for example libflac14 alone) does not pass
for an alternative group. Version constraints in parentheses are ignored.
"""

import re
import sys

# Required runtime groups: one frozenset of alternatives per entry.
REQUIRED = [
    {"libgtk-3-0"},
    {"libsecret-1-0"},
    {"libnotify4"},
    {"libayatana-appindicator3-1"},
    {"libasound2"},
    {"libcurl4"},
    {"libkeybinder-3.0-0"},
    {"libopusfile0"},
    {"libogg0"},
    # libFLAC package name differs per release: libflac14 on Debian 13 (trixie),
    # libflac12t64 on Ubuntu 24.04 (noble, t64 transition), libflac12 on Debian 12,
    # libflac8 on older releases. Verified on packages.debian.org and
    # packages.ubuntu.com.
    {"libflac14", "libflac12t64", "libflac12", "libflac8"},
]


def parse_groups(value: str) -> list[frozenset[str]]:
    groups = []
    for entry in value.split(","):
        entry = re.sub(r"\([^)]*\)", "", entry).strip()
        if not entry:
            continue
        groups.append(frozenset(alt.strip() for alt in entry.split("|") if alt.strip()))
    return groups


def read_depends(argv: list[str]) -> str:
    if argv[1] == "--field":
        return argv[2]
    if argv[1] == "-":
        return sys.stdin.read().strip()
    # A field continues on lines that start with a space (Debian control rule).
    value = None
    for line in open(argv[1], encoding="utf-8"):
        if line.startswith("Depends:"):
            value = line.split(":", 1)[1]
        elif value is not None and line.startswith(" "):
            value += " " + line.strip()
        elif value is not None:
            break
    return (value or "").strip()


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    value = read_depends(sys.argv)
    if not value:
        print("::error::no Depends field found")
        return 1
    groups = parse_groups(value)
    missing = [sorted(req) for req in REQUIRED if req not in groups]
    for req in missing:
        print(f"::error::Depends lacks required group: {' | '.join(req)}")
    if missing:
        return 1
    print(f"  ok: {len(REQUIRED)} required Depends groups present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
