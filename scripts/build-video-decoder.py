#!/usr/bin/env python3
"""Build the audio-only, LGPL FFmpeg helper; no decoder is downloaded at runtime.

The helper extracts audio from imported videos (ADR 0037) and compresses the
upload copy of cloud transcription to Opus/WebM (#177). libopus (BSD-3-Clause)
is its only external library; it is built from a pinned release tarball and
linked statically, so the helper stays LGPL.

Linux/macOS need a C compiler and make. Windows uses the existing Visual Studio
toolchain plus MSYS2's bash/make (C:/msys64/usr/bin) and CMake (passed by the
runner build via --cmake) for libopus; no MSYS runtime is shipped. The complete
unmodified sources and this build recipe accompany the executable.
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
# libopus for the Opus encoder of the upload copy; same pin as the Ogg/Opus
# decoder of the app (scripts/build-opus-macos.sh, windows/runner/opus_audio.cmake).
OPUS_VERSION = "1.5.2"
OPUS_SHA256 = "65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
RECIPE = Path(__file__).resolve()
ROOT = RECIPE.parent if (RECIPE.parent / f"ffmpeg-{VERSION}.tar.xz").exists() else RECIPE.parent.parent
FLAGS = [
    "--disable-everything", "--disable-autodetect", "--disable-network",
    "--disable-gpl", "--disable-nonfree", "--disable-version3",
    "--disable-doc", "--disable-debug", "--disable-x86asm",
    "--disable-shared", "--enable-static", "--enable-ffmpeg",
    "--enable-protocol=file,pipe", "--enable-demuxer=mov,matroska,mpegps,mpegts,pcm_s16le",
    "--enable-decoder=mp2,ac3,eac3,pcm_dvd,aac,alac,mp3,flac,opus,vorbis,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f64le",
    "--enable-parser=ac3,aac,mpegaudio,flac,opus,vorbis",
    "--enable-encoder=pcm_s16le,libopus", "--enable-muxer=pcm_s16le,webm",
    "--enable-libopus",
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


def fetch_source(cache, name, url, expected_sha256):
    """The verified archive [name] in [cache]: from the recipe directory (a
    rebuild from the bundled sources) or downloaded."""
    archive = cache / name
    if not archive.exists() and (RECIPE.parent / name).exists():
        shutil.copy2(RECIPE.parent / name, archive)
    if not archive.exists():
        download_archive(url, archive, expected_sha256)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != expected_sha256:
        raise SystemExit(f"video-decoder: {name} SHA-256 mismatch")
    return archive


def extract_safely(archive, work):
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


def pkg_config_shim(path, prefix, windows):
    """FFmpeg's configure finds libopus only through pkg-config, which the
    build machines do not have. This shim answers exactly the calls configure
    makes for the static libopus in [prefix] and nothing else."""
    include = (prefix / "include").as_posix()
    libs = f"-L{(prefix / 'lib').as_posix()} -lopus" + ("" if windows else " -lm")
    path.write_text(
        "#!/bin/sh\n"
        "# Generated by build-video-decoder.py: pkg-config for the pinned libopus only.\n"
        "out=\n"
        "for arg do\n"
        "  case \"$arg\" in\n"
        "    --version) echo 0.29.2; exit 0 ;;\n"
        f"    --cflags) out='-I{include}/opus' ;;\n"
        f"    --libs) out='{libs}' ;;\n"
        f"    --variable=includedir) out='{include}' ;;\n"
        "    --*) ;;\n"
        "    opus) ;;\n"
        "    *) echo \"Package $arg was not found\" >&2; exit 1 ;;\n"
        "  esac\n"
        "done\n"
        "[ -n \"$out\" ] && printf '%s\\n' \"$out\"\n"
        "exit 0\n"
    )
    path.chmod(0o755)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["linux", "macos", "windows"], required=True)
    parser.add_argument("--vcvars", help="Visual Studio vcvars64.bat (Windows only)")
    parser.add_argument("--cmake", help="CMake for the libopus build (Windows only; default: cmake on PATH)")
    args = parser.parse_args()
    stage = ROOT / ".build/video-decoder" / args.platform
    stamp = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    executable = "ffmpeg.exe" if args.platform == "windows" else "ffmpeg"
    opus_name = f"opus-{OPUS_VERSION}.tar.gz"
    required_files = [executable, f"ffmpeg-{VERSION}.tar.xz", opus_name, "COPYING.LGPLv2.1", "COPYING.libopus", "SOURCE.txt", "build-video-decoder.py"]
    if (stage / "stamp").exists() and (stage / "stamp").read_text() == stamp and all((stage / name).exists() for name in required_files):
        print("video-decoder: up to date")
        return
    cache = ROOT / ".build/video-decoder-source"
    cache.mkdir(parents=True, exist_ok=True)
    archive = fetch_source(cache, f"ffmpeg-{VERSION}.tar.xz", f"https://ffmpeg.org/releases/ffmpeg-{VERSION}.tar.xz", SHA256)
    opus_archive = fetch_source(cache, opus_name, f"https://downloads.xiph.org/releases/opus/{opus_name}", OPUS_SHA256)
    work = cache / args.platform
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    extract_safely(archive, work)
    extract_safely(opus_archive, work)
    source_dir = work / f"ffmpeg-{VERSION}"
    opus_dir = work / f"opus-{OPUS_VERSION}"
    opus_prefix = work / "opus-prefix"
    shim = work / "pkg-config-opus.sh"
    pkg_config_shim(shim, opus_prefix, args.platform == "windows")
    flags = list(FLAGS) + ["--pkg-config=" + shim.as_posix(), "--pkg-config-flags=--static"]
    opus_cflags = "-O2"
    if args.platform == "macos":
        if platform.machine() != "arm64":
            raise SystemExit("video-decoder: build macOS on Apple Silicon")
        flags += ["--arch=aarch64", "--extra-cflags=-mmacosx-version-min=13.0", "--extra-ldflags=-mmacosx-version-min=13.0"]
        opus_cflags += " -mmacosx-version-min=13.0"
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
            cmake = args.cmake or shutil.which("cmake")
            if not bash.exists() or not args.vcvars or not cmake:
                raise SystemExit("video-decoder: Windows requires MSYS2 bash/make, --vcvars vcvars64.bat and CMake; see BUILD.md")
            import shlex
            script = work / "build.sh"
            script.write_text("#!/bin/sh\nset -eu\ncd " + shlex.quote(source_dir.as_posix()) + "\n./configure " + " ".join(map(shlex.quote, flags)) + "\nmake -j" + jobs + " ffmpeg.exe\n")
            # libopus with the static C runtime (/MT), the default of FFmpeg's
            # MSVC toolchain, so both halves link into one executable.
            opus_build = work / "opus-build"
            command = work / "build.cmd"
            command.write_text(
                "@echo off\n"
                f'call "{args.vcvars}" >nul\nif errorlevel 1 exit /b 1\n'
                f'"{cmake}" -S "{opus_dir}" -B "{opus_build}" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release'
                " -DCMAKE_POLICY_DEFAULT_CMP0091=NEW -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
                " -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_SHARED_LIBRARY=OFF"
                f' -DCMAKE_INSTALL_PREFIX="{opus_prefix}"\nif errorlevel 1 exit /b 1\n'
                f'"{cmake}" --build "{opus_build}" --target install\nif errorlevel 1 exit /b 1\n'
                f'"{bash}" "{script.as_posix()}"\n'
            )
            env["PATH"] += ";" + str(msys / "usr/bin")
            result = subprocess.run(["cmd.exe", "/c", str(command)], env=env, stdout=output, stderr=subprocess.STDOUT)
        else:
            opus_env = dict(env, CFLAGS=opus_cflags)
            steps = [
                (["bash", "./configure", "--prefix=" + str(opus_prefix), "--disable-shared", "--enable-static",
                  "--disable-doc", "--disable-extra-programs"], opus_dir, opus_env),
                (["make", "-j" + jobs, "install"], opus_dir, opus_env),
                (["bash", "./configure", *flags], source_dir, env),
                (["make", "-j" + jobs, "ffmpeg"], source_dir, env),
            ]
            for command, cwd, step_env in steps:
                result = subprocess.run(command, cwd=cwd, env=step_env, stdout=output, stderr=subprocess.STDOUT)
                if result.returncode:
                    break
    if result.returncode:
        raise SystemExit(f"video-decoder: build failed; see {log}")
    config = (source_dir / "config.h").read_text(encoding="latin-1")
    if '#define FFMPEG_LICENSE "LGPL version 2.1 or later"' not in config:
        raise SystemExit("video-decoder: unexpected FFmpeg licence; refusing to bundle")
    components = (source_dir / "config_components.h").read_text(encoding="latin-1")
    for required in ["MOV_DEMUXER", "MATROSKA_DEMUXER", "MPEGPS_DEMUXER", "MPEGTS_DEMUXER", "PCM_S16LE_DEMUXER",
                     "PCM_S16LE_MUXER", "PCM_S16LE_ENCODER", "LIBOPUS_ENCODER", "WEBM_MUXER", "AAC_DECODER",
                     "MP2_DECODER", "AC3_DECODER", "EAC3_DECODER", "PCM_DVD_DECODER", "OPUS_DECODER",
                     "VORBIS_DECODER", "ARESAMPLE_FILTER"]:
        if f"#define CONFIG_{required} 1" not in components:
            raise SystemExit(f"video-decoder: required component missing: {required}")
    # The shim path is local to the build machine; the shipped recipe names it.
    public_flags = ["--pkg-config=<pkg-config shim of build-video-decoder.py>" if flag.startswith("--pkg-config=") else flag for flag in flags]
    stage.mkdir(parents=True, exist_ok=True)
    for old_source in [*stage.glob("ffmpeg-*.tar.xz"), *stage.glob("opus-*.tar.gz")]:
        old_source.unlink()
    shutil.copy2(source_dir / executable, stage / executable)
    shutil.copy2(source_dir / "COPYING.LGPLv2.1", stage / "COPYING.LGPLv2.1")
    shutil.copy2(opus_dir / "COPYING", stage / "COPYING.libopus")
    shutil.copy2(archive, stage / archive.name)
    shutil.copy2(opus_archive, stage / opus_archive.name)
    shutil.copy2(__file__, stage / "build-video-decoder.py")
    (stage / "SOURCE.txt").write_text(
        f"FFmpeg {VERSION}; LGPL-2.1-or-later\nhttps://ffmpeg.org/\nSource: {archive.name}\nSHA256: {SHA256}\n"
        f"Unmodified sources. One external codec library, linked statically:\n"
        f"libopus {OPUS_VERSION}; BSD-3-Clause (COPYING.libopus)\nhttps://opus-codec.org/\n"
        f"Source: {opus_archive.name}\nSHA256: {OPUS_SHA256}\n"
        f"Rebuild: python3 build-video-decoder.py --platform <linux|macos|windows>\n"
        f"Configure: {' '.join(public_flags)}\n")
    (stage / "stamp").write_text(stamp)
    print(f"video-decoder: built {stage / executable} ({(stage / executable).stat().st_size} bytes)")


if __name__ == "__main__":
    main()
