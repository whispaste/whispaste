#!/usr/bin/env python3
"""Checks a Debian Depends field against the required runtime groups.

Usage:
  check_depends.py <control.template>     read the Depends field from a template
  check_depends.py --field "<Depends>"    check a Depends value given directly
  dpkg-deb -f pkg.deb Depends | check_depends.py -   read the value from stdin

Each comma-separated entry is one group of `|` alternatives. A required group
must appear exactly as written (same alternatives, nothing missing). A
forbidden package must not appear in any group: libFLAC ships inside the
bundle (#84), and an apt alternative for it would only satisfy apt while the
binary still needs one exact soname. Version constraints in parentheses are
ignored.
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
    # parecord records, pactl lists the microphones (the `record` package
    # starts both); without them Linux cannot record at all (#85). The
    # package only needs libpulse, it works on PipeWire's pulse server too.
    {"pulseaudio-utils"},
]

# Bundled in lib/ instead (scripts/check-linux-bundled-codecs.sh), by prefix.
FORBIDDEN_PREFIXES = ("libflac",)


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
    forbidden = sorted(
        name for group in groups for name in group if name.startswith(FORBIDDEN_PREFIXES)
    )
    for name in forbidden:
        print(f"::error::Depends names {name}, which ships inside the bundle")
    if missing or forbidden:
        return 1
    print(f"  ok: {len(REQUIRED)} required Depends groups present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
