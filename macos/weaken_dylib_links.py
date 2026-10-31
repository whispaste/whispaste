#!/usr/bin/env python3
"""weaken_dylib_links.py — Xcode build phase (MAS configuration only).

Flutter's own generated `Flutter-Release.xcconfig` hardcodes
`#include "Pods-Runner.release.xcconfig"` regardless of which actual Xcode
configuration is building (Flutter has no concept of a 4th "MAS" build
type distinct from "release"). The MAS project-level Xcode configuration
also reuses the same `Release.xcconfig` file reference as the real Release
config. So the MAS executable ends up hard-linked (-framework "X", i.e. a
required LC_LOAD_DYLIB) against frameworks strip_mas_incompatible_
frameworks.sh deletes from the built MAS app bundle (Sparkle.framework —
Apple rejects its unsandboxed helper executables; auto_updater_macos.
framework — it hard-requires Sparkle's SPUStandardUserDriver class via
eager Objective-C class binding, which no amount of dylib-level
weak-linking prevents, since that's a per-symbol bind flag, not a
per-dylib one). dyld then refuses to even start the process ("Library not
loaded: @rpath/.../Sparkle") — confirmed by actually launching a local MAS
test build, not just checking that Transporter accepted the upload.

A Podfile post_install hook cannot fix this: nothing in the real build
ever reads Pods-Runner.mas.xcconfig (verified via `xcodebuild
-showBuildSettings` and by tracing the actual clang/ld invocation in a
build log). The only place left to intervene is the linked Mach-O binary
itself, after linking but before code signing — flip the load command for
each stripped framework from LC_LOAD_DYLIB (required) to
LC_LOAD_WEAK_DYLIB (optional, dyld skips it silently if the file is
absent). Safe: the Dart/Swift layers already skip all Sparkle/auto-update
usage for the MAS build (see deploy_channel_service.dart's
isExternallyManaged check and GeneratedPluginRegistrant.swift's
`#if !MAS_BUILD` guard around AutoUpdaterMacosPlugin.register), so no
symbol from either framework is ever actually called at runtime.

Both command structures (dylib_command) are byte-identical in layout; only
the leading `cmd` field's tag value differs, so this is a safe, minimal,
well-defined patch (the same technique used by e.g. Facebook's `fbweaken`
tool for the same purpose). This only weakens the *load command* on the
binary passed on the command line — it does not (and cannot) fix internal
symbol references inside a stripped framework's own binary, which is why
auto_updater_macos.framework itself must also be deleted from the bundle
(see strip_mas_incompatible_frameworks.sh) rather than merely weak-linked.
"""
import struct
import sys

LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x80000018

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA


def weaken_slice(data: bytearray, offset: int, target_names: list[bytes]) -> int:
    # Fat headers (fat_header/fat_arch) are always big-endian, but each thin
    # mach_header_64 slice is stored in the target's native byte order —
    # little-endian for both x86_64 and arm64 — so this magic check (and
    # everything else read from within the slice) uses "<", not ">".
    magic = struct.unpack_from("<I", data, offset)[0]
    if magic != MH_MAGIC_64:
        return 0
    ncmds = struct.unpack_from("<I", data, offset + 16)[0]
    pos = offset + 32  # sizeof(mach_header_64)
    patched = 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, pos)
        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            name_off = struct.unpack_from("<I", data, pos + 8)[0]
            name_start = pos + name_off
            name_end = data.index(b"\x00", name_start)
            name = bytes(data[name_start:name_end])
            if cmd == LC_LOAD_DYLIB and any(name.endswith(t) for t in target_names):
                struct.pack_into("<I", data, pos, LC_LOAD_WEAK_DYLIB)
                patched += 1
        pos += cmdsize
    return patched


def weaken_binary(path: str, target_names: list[bytes]) -> int:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    magic = struct.unpack_from(">I", data, 0)[0]
    total_patched = 0
    if magic in (FAT_MAGIC, FAT_CIGAM):
        nfat = struct.unpack_from(">I", data, 4)[0]
        for i in range(nfat):
            arch_off = 8 + i * 20
            slice_offset = struct.unpack_from(">I", data, arch_off + 8)[0]
            total_patched += weaken_slice(data, slice_offset, target_names)
    else:
        total_patched += weaken_slice(data, 0, target_names)

    if total_patched:
        with open(path, "wb") as f:
            f.write(data)
    return total_patched


DEFAULT_TARGETS = [
    b"Sparkle.framework/Versions/B/Sparkle",
    b"auto_updater_macos.framework/Versions/A/auto_updater_macos",
]

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: weaken_dylib_links.py <path-to-executable>", file=sys.stderr)
        sys.exit(1)

    binary_path = sys.argv[1]
    n = weaken_binary(binary_path, DEFAULT_TARGETS)
    print(f"weaken_dylib_links: patched {n} load command(s) in {binary_path}")
