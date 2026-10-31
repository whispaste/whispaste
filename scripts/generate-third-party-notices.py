#!/usr/bin/env python3
"""generate-third-party-notices.py — builds THIRD_PARTY_NOTICES.md at the repo root.

Sources (all read from the repository, nothing typed in twice):
  * pubspec.lock                          Dart/Flutter packages (hosted + SDK)
  * PUB_CACHE/hosted/pub.dev/<pkg>-<ver>  the LICENSE file of each hosted package
  * lib/core/licenses/third_party_licenses.dart  native library notices
  * assets/licenses/*.txt                 the native library licence texts
  * MODELS below                          model weights downloaded on request;
                                          each download URL must occur in lib/

Output is deterministic (sorted, no timestamps), so `--check` can prove the
committed file is current. Fails loudly on a missing licence file: a notices
file with a silent gap is worse than none.

Usage:
  python3 scripts/generate-third-party-notices.py            # write the file
  python3 scripts/generate-third-party-notices.py --check    # exit 1 if stale
  python3 scripts/generate-third-party-notices.py --stdout   # print only
"""
from __future__ import annotations

import difflib
import hashlib
import os
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "THIRD_PARTY_NOTICES.md"

# Model weights WhisPaste downloads on request. `licence` is the licence named by
# the upstream model card / repository; `source` must appear in lib/ (checked).
MODELS = [
    {
        "name": "Whisper (ggml conversions of OpenAI Whisper)",
        "source": "https://huggingface.co/ggerganov/whisper.cpp",
        "licence": "MIT (OpenAI Whisper weights)",
        "note": "Upstream model cards: verify before each release.",
    },
    {
        "name": "Parakeet TDT 0.6B v3 (NVIDIA)",
        "source": "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3",
        "licence": "CC-BY-4.0",
        "note": "Attribution in the app's licence page (see third_party_licenses.dart).",
    },
    {
        "name": "Parakeet TDT 0.6B v3, GGUF conversion",
        "source": "https://huggingface.co/ggml-org/parakeet-GGUF",
        "licence": "CC-BY-4.0 (derived from NVIDIA)",
        "note": "Format conversion, no retraining.",
    },
    {
        "name": "Parakeet TDT 0.6B v3, int8 ONNX export (sherpa-onnx)",
        "source": "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
        "licence": "CC-BY-4.0 (derived from NVIDIA)",
        "note": "Format conversion, no retraining.",
    },
    {
        "name": "Gemma 4 E2B-it (Q4_K_M GGUF)",
        "source": "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF",
        "licence": "Apache-2.0 (https://ai.google.dev/gemma/apache_2)",
        "note": "Shipped as an on-request download. Licence checked 2026-10-17 via https://ai.google.dev/gemma/docs/gemma_4_license, which redirects (301) to the Apache 2.0 page. The huggingface.co model card was not checked (host blocked on this Mac).",
    },
]

FORBIDDEN = re.compile(r"espeak|piper", re.IGNORECASE)


def pub_cache() -> Path:
    env = os.environ.get("PUB_CACHE")
    if env:
        return Path(env)
    # Dart's default on Windows is %LOCALAPPDATA%\Pub\Cache, not ~/.pub-cache.
    local = os.environ.get("LOCALAPPDATA")
    if os.name == "nt" and local:
        return Path(local) / "Pub" / "Cache"
    return Path.home() / ".pub-cache"


def flutter_root() -> Path | None:
    env = os.environ.get("FLUTTER_ROOT")
    if env:
        return Path(env)
    exe = shutil.which("flutter")
    if not exe:
        return None
    return Path(os.path.realpath(exe)).parent.parent


def read_lock() -> list[dict]:
    """Minimal pubspec.lock reader: name, version, source for each package."""
    pkgs: list[dict] = []
    cur: dict | None = None
    in_packages = False
    for raw in (REPO / "pubspec.lock").read_text(encoding="utf-8").splitlines():
        if raw == "packages:":
            in_packages = True
            continue
        if not in_packages:
            continue
        if raw and not raw.startswith(" "):  # next top-level key ("sdks:")
            break
        if re.match(r"^  \S", raw):  # "  name:" starts a package
            cur = {"name": raw.strip().rstrip(":")}
            pkgs.append(cur)
        elif cur is not None:
            m = re.match(r'^    (source|version): "?([^"]*)"?$', raw)
            if m:
                cur[m.group(1)] = m.group(2)
    return pkgs


LICENCE_NAMES = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md"]


def find_licence(base: Path) -> Path | None:
    for n in LICENCE_NAMES:
        if (base / n).is_file():
            return base / n
    return None


def normalise(text: str) -> str:
    return "\n".join(line.rstrip() for line in text.strip().splitlines()) + "\n"


def dart_packages() -> tuple[dict[str, list[str]], list[str]]:
    """Returns (licence text -> [package versions]), local/path package names."""
    groups: dict[str, list[str]] = {}
    local: list[str] = []
    missing: list[str] = []
    sdk_names: list[str] = []
    flutter = flutter_root()
    cache = pub_cache() / "hosted" / "pub.dev"
    for pkg in read_lock():
        name = pkg["name"]
        source = pkg.get("source")
        version = pkg.get("version", "?")
        if source == "path":
            # A vendored fork keeps its upstream LICENSE and is listed with it;
            # only packages without one are this project's own (MIT) code.
            lic = find_licence(REPO / "packages" / name)
            if lic is None:
                local.append(name)
            else:
                groups.setdefault(
                    normalise(lic.read_text(encoding="utf-8", errors="replace")), []
                ).append(f"{name} {version} (vendored fork)")
            continue
        if source == "sdk":
            sdk_names.append(name)
            continue
        if source != "hosted":
            missing.append(f"{name} (unsupported source {source})")
            continue
        lic = find_licence(cache / f"{name}-{version}")
        if lic is None:
            missing.append(f"{name} {version}")
            continue
        groups.setdefault(normalise(lic.read_text(encoding="utf-8", errors="replace")), []).append(
            f"{name} {version}"
        )
    if sdk_names:
        if flutter is None or find_licence(flutter) is None:
            missing.append("Flutter SDK LICENSE (set FLUTTER_ROOT)")
        else:
            text = normalise(find_licence(flutter).read_text(encoding="utf-8", errors="replace"))
            groups.setdefault(text, []).extend(f"{n} (Flutter SDK)" for n in sdk_names)
    if missing:
        sys.exit("error: no licence file for: " + ", ".join(missing))
    return groups, local


def native_entries() -> list[tuple[str, str, str]]:
    """(title, asset file, version comment) from the native licence map."""
    src = (REPO / "lib/core/licenses/third_party_licenses.dart").read_text(encoding="utf-8")
    block = re.search(r"const nativeLibraryLicenses = <String, String>\{(.*?)\};", src, re.S)
    if not block:
        sys.exit("error: nativeLibraryLicenses map not found")
    out = []
    for m in re.finditer(r"'([^']+)':\s*'([^']+)',?\s*(?://\s*(.*))?", block.group(1)):
        out.append((m.group(1), m.group(2), (m.group(3) or "").strip()))
    if not out:
        sys.exit("error: no native library entries parsed")
    return out


def check_model_sources() -> None:
    lib_text = "\n".join(
        p.read_text(encoding="utf-8", errors="replace")
        for p in (REPO / "lib").rglob("*.dart")
    )
    for model in MODELS:
        base = model["source"].split("/resolve/")[0]
        if base not in lib_text:
            sys.exit(f"error: model source {base} is not referenced in lib/")


def render() -> str:
    check_model_sources()
    groups, local = dart_packages()
    natives = native_entries()

    lines: list[str] = []
    w = lines.append
    w("# Third-party notices")
    w("")
    w("WhisPaste itself is MIT-licensed (see [LICENSE](LICENSE)). This file lists the")
    w("third-party software and models that the app ships or downloads on request.")
    w("")
    w("<!-- Generated by scripts/generate-third-party-notices.py from pubspec.lock,")
    w("     lib/core/licenses/third_party_licenses.dart and the model list in that script.")
    w("     Do not edit by hand: run the script. -->")
    w("")
    w("## 1. Native libraries shipped with the app")
    w("")
    w("| Library | Version / pin | Licence | Notice text |")
    w("|---|---|---|---|")
    for title, asset, version in natives:
        w(f"| {title} | {version or '-'} | see text | `assets/licenses/{asset}` |")
    w("")
    w("The sherpa-onnx C API is built from the pinned tag without text-to-speech")
    w("(`-DSHERPA_ONNX_ENABLE_TTS=OFF`, see `scripts/build-sherpa-onnx.sh`), so no")
    w("speech-synthesis code is compiled in. The release pipeline checks every")
    w("bundle for speech-synthesis engine code before publishing.")
    w("")
    w("## 2. Models downloaded on request")
    w("")
    w("| Model | Source | Licence |")
    w("|---|---|---|")
    for m in MODELS:
        w(f"| {m['name']} | <{m['source']}> | {m['licence']} |")
    w("")
    for m in MODELS:
        w(f"- {m['name']}: {m['note']}")
    w("")
    w("## 3. Dart and Flutter packages")
    w("")
    w("Packages are grouped by identical licence text. Local workspace packages"
      f" ({', '.join(sorted(local)) or 'none'}) are part of this project and MIT-licensed.")
    w("")
    for text in sorted(groups, key=lambda t: (-len(groups[t]), t)):
        pkgs = sorted(groups[text])
        w(f"### {len(pkgs)} package(s): {text.splitlines()[0][:80]}")
        w("")
        w("Packages: " + ", ".join(pkgs))
        w("")
        w("```text")
        w(text.rstrip())
        w("```")
        w("")
    w("## 4. Native library licence texts")
    w("")
    for title, asset, _ in natives:
        text = (REPO / "assets/licenses" / asset).read_text(encoding="utf-8").rstrip()
        w(f"### {title}")
        w("")
        w("```text")
        w(text)
        w("```")
        w("")
    rendered = "\n".join(lines).rstrip() + "\n"
    if FORBIDDEN.search(rendered):
        hit = FORBIDDEN.search(rendered).group(0)
        sys.exit(f"error: generated notices mention {hit!r}; espeak-ng/piper must not be listed as shipped")
    return rendered


def main(argv: list[str]) -> int:
    text = render()
    if "--stdout" in argv:
        sys.stdout.write(text)
        return 0
    if "--check" in argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != text:
            diff = difflib.unified_diff(
                current.splitlines(keepends=True),
                text.splitlines(keepends=True),
                fromfile="THIRD_PARTY_NOTICES.md (committed)",
                tofile="THIRD_PARTY_NOTICES.md (generated)",
            )
            sys.stderr.writelines(diff)
            print("THIRD_PARTY_NOTICES.md is stale: run scripts/generate-third-party-notices.py", file=sys.stderr)
            return 1
        print("THIRD_PARTY_NOTICES.md is up to date.")
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT} ({len(text.encode('utf-8'))} bytes, sha256 {hashlib.sha256(text.encode()).hexdigest()[:12]})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
