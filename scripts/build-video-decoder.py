#!/usr/bin/env python3
"""Build the audio-only, LGPL FFmpeg helper; no decoder is downloaded at runtime.

Linux/macOS need a C compiler and make. Windows uses the existing Visual Studio
toolchain plus MSYS2's bash/make (C:/msys64/usr/bin); no MSYS runtime is shipped.
The complete unmodified source and this build recipe accompany the executable.
"""

import argparse
import hashlib
import http.client
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import time
import urllib.request


VERSION = "9.0.2"
SHA256 = "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
RECIPE = Path(__file__).resolve()
ROOT = RECIPE.parent if (RECIPE.parent / f"ffmpeg-{VERSION}.tar.xz").exists() else RECIPE.parent.parent
FLAGS = [
    "--disable-everything", "--disable-autodetect", "--disable-network",
    "--disable-gpl", "--disable-nonfree", "--disable-version3",
    "--disable-doc", "--disable-debug", "--disable-x86asm",
    "--disable-shared", "--enable-static", "--enable-ffmpeg",
    "--enable-protocol=file,pipe", "--enable-demuxer=mov,matroska",
    "--enable-decoder=aac,alac,mp3,flac,opus,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f64le",
    "--enable-parser=aac,mpegaudio,flac,opus,vorbis",
    "--enable-encoder=pcm_s16le", "--enable-muxer=pcm_s16le",
    "--enable-filter=aresample,aformat,anull",
]


def download_archive(url, archive, expected_sha256):
    """Publish only verified bytes; bound stalls and retain no failed partial file."""
    part = archive.with_suffix(".part")
    deadline = time.monotonic() + 180
    try:
        for attempt in range(1, 4):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("video-decoder: source download budget exhausted")
            print(f"video-decoder: downloading source (attempt {attempt}/3)", flush=True)
            try:
                digest = hashlib.sha256()
                received = 0
                report_at = time.monotonic() + 15
                # One socket operation may extend the total budget by at most 15s.
                with urllib.request.urlopen(url, timeout=min(15, remaining)) as response, part.open("wb") as output:
                    while True:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("video-decoder: source download budget exhausted")
                        block = response.read(64 * 1024)
                        if not block:
                            break
                        output.write(block)
                        digest.update(block)
                        received += len(block)
                        now = time.monotonic()
                        if now >= report_at:
                            print(f"video-decoder: downloaded {received} bytes; {max(0, int(deadline-now))}s budget remaining", flush=True)
                            report_at = now + 15
                if digest.hexdigest() != expected_sha256:
                    raise ValueError("video-decoder: FFmpeg source SHA-256 mismatch")
                part.replace(archive)
                print(f"video-decoder: source verified ({received} bytes)", flush=True)
                return
            except (OSError, http.client.IncompleteRead) as error:
                print(f"video-decoder: download attempt {attempt} failed ({type(error).__name__})", flush=True)
                if attempt == 3:
                    raise
    finally:
        part.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["linux", "macos", "windows"], required=True)
    parser.add_argument("--vcvars", help="Visual Studio vcvars64.bat (Windows only)")
    args = parser.parse_args()
    stage = ROOT / ".build/video-decoder" / args.platform
    stamp = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    executable = "ffmpeg.exe" if args.platform == "windows" else "ffmpeg"
    required_files = [executable, f"ffmpeg-{VERSION}.tar.xz", "COPYING.LGPLv2.1", "SOURCE.txt", "build-video-decoder.py"]
    if (stage / "stamp").exists() and (stage / "stamp").read_text() == stamp and all((stage / name).exists() for name in required_files):
        print("video-decoder: up to date")
        return
    cache = ROOT / ".build/video-decoder-source"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"ffmpeg-{VERSION}.tar.xz"
    if not archive.exists() and (RECIPE.parent / archive.name).exists():
        shutil.copy2(RECIPE.parent / archive.name, archive)
    if not archive.exists():
        download_archive(f"https://ffmpeg.org/releases/{archive.name}", archive, SHA256)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit("video-decoder: FFmpeg source SHA-256 mismatch")
    work = cache / args.platform
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    with tarfile.open(archive) as source:
        # Verified upstream archive. Python < 3.9.17 (Xcode's system 3.9.6)
        # lacks extraction filters, so validate every member ourselves:
        # no path, symlink or hardlink may leave the build directory and no
        # device/FIFO entries are allowed.
        root = work.resolve()
        for entry in source.getmembers():
            if entry.isdev() or not (work / entry.name).resolve().is_relative_to(root):
                raise SystemExit("video-decoder: invalid archive path")
            if entry.issym() and not (work / entry.name).parent.joinpath(entry.linkname).resolve().is_relative_to(root):
                raise SystemExit("video-decoder: invalid archive link")
            if entry.islnk() and not (work / entry.linkname).resolve().is_relative_to(root):
                raise SystemExit("video-decoder: invalid archive link")
        if hasattr(tarfile, "data_filter"):
            source.extractall(work, filter="data")
        else:
            source.extractall(work)
    source_dir = work / f"ffmpeg-{VERSION}"
    flags = list(FLAGS)
    if args.platform == "macos":
        if platform.machine() != "arm64":
            raise SystemExit("video-decoder: build macOS on Apple Silicon")
        flags += ["--arch=aarch64", "--extra-cflags=-mmacosx-version-min=13.0", "--extra-ldflags=-mmacosx-version-min=13.0"]
    if args.platform == "windows":
        flags += ["--toolchain=msvc", "--arch=x86_64", "--target-os=win64"]
    # Serial configuration followed by a bounded compile. Keep verbose build
    # output in a file; print its location on failure.
    log = cache / f"{args.platform}.log"
    jobs = str(min(os.cpu_count() or 2, 8))
    env = dict(os.environ)
    with log.open("w") as output:
        if args.platform == "windows":
            msys = Path(os.environ.get("WP_MSYS2_ROOT") or "C:/msys64")
            bash = msys / "usr/bin/bash.exe"
            if not bash.exists() or not args.vcvars:
                raise SystemExit("video-decoder: Windows requires MSYS2 bash/make and --vcvars vcvars64.bat; see BUILD.md")
            import shlex
            script = work / "build.sh"
            script.write_text("#!/bin/sh\nset -eu\ncd " + shlex.quote(source_dir.as_posix()) + "\n./configure " + " ".join(map(shlex.quote, flags)) + "\nmake -j" + jobs + " ffmpeg.exe\n")
            command = work / "build.cmd"
            command.write_text(f'@echo off\ncall "{args.vcvars}" >nul\nif errorlevel 1 exit /b 1\n"{bash}" "{script.as_posix()}"\n')
            env["PATH"] += ";" + str(msys / "usr/bin")
            result = subprocess.run(["cmd.exe", "/c", str(command)], env=env, stdout=output, stderr=subprocess.STDOUT)
        else:
            result = subprocess.run(["bash", "./configure", *flags], cwd=source_dir, env=env, stdout=output, stderr=subprocess.STDOUT)
            if result.returncode == 0:
                result = subprocess.run(["make", "-j" + jobs, "ffmpeg"], cwd=source_dir, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise SystemExit(f"video-decoder: build failed; see {log}")
    config = (source_dir / "config.h").read_text(encoding="latin-1")
    if '#define FFMPEG_LICENSE "LGPL version 2.1 or later"' not in config:
        raise SystemExit("video-decoder: unexpected FFmpeg licence; refusing to bundle")
    components = (source_dir / "config_components.h").read_text(encoding="latin-1")
    for required in ["MOV_DEMUXER", "MATROSKA_DEMUXER", "PCM_S16LE_MUXER", "PCM_S16LE_ENCODER", "AAC_DECODER", "OPUS_DECODER", "VORBIS_DECODER", "ARESAMPLE_FILTER"]:
        if f"#define CONFIG_{required} 1" not in components:
            raise SystemExit(f"video-decoder: required component missing: {required}")
    stage.mkdir(parents=True, exist_ok=True)
    for old_source in stage.glob("ffmpeg-*.tar.xz"):
        old_source.unlink()
    shutil.copy2(source_dir / executable, stage / executable)
    shutil.copy2(source_dir / "COPYING.LGPLv2.1", stage / "COPYING.LGPLv2.1")
    shutil.copy2(archive, stage / archive.name)
    shutil.copy2(__file__, stage / "build-video-decoder.py")
    (stage / "SOURCE.txt").write_text(f"FFmpeg {VERSION}; LGPL-2.1-or-later\nhttps://ffmpeg.org/\nSource: {archive.name}\nSHA256: {SHA256}\nUnmodified source; no external codec libraries.\nConfigure: {' '.join(flags)}\n")
    (stage / "stamp").write_text(stamp)
    print(f"video-decoder: built {stage / executable} ({(stage / executable).stat().st_size} bytes)")


if __name__ == "__main__":
    main()
