#!/usr/bin/env bash
# Builds libogg, libopus and opusfile as universal (arm64 + x86_64) static
# libraries for the macOS app (WP-35b). Sources are pinned by URL and SHA-256;
# nothing comes from Homebrew or the system. Output: .build/opus-macos/{include,lib}.
#
# Idempotent: .build/opus-macos/stamp records the pins and the deployment
# target. When it matches and the libraries exist, the script returns at once.
# Uses configure/make (shipped in the tarballs), not CMake, so no extra tool is
# needed on the build machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/opus-macos"
SRC="$ROOT/.build/opus-src"
MIN="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
ARCHS=(arm64 x86_64)
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# name version url sha256 (pins; change them together with the stamp).
PKGS=(
  "libogg 1.3.6 https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.gz 83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638"
  "opus 1.5.2 https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz 65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
  "opusfile 0.12 https://downloads.xiph.org/releases/opus/opusfile-0.12.tar.gz 118d8601c12dd6a44f52423e68ca9083cc9f2bfe72da7a8c1acb22a80ae3550b"
)

STAMP_WANT="$(printf '%s\n' "${PKGS[@]}" "min=$MIN" "archs=${ARCHS[*]}")"
LIBS=("$OUT/lib/libogg.a" "$OUT/lib/libopus.a" "$OUT/lib/libopusfile.a")
if [[ -f "$OUT/stamp" && "$(cat "$OUT/stamp")" == "$STAMP_WANT" ]] &&
   [[ -f "${LIBS[0]}" && -f "${LIBS[1]}" && -f "${LIBS[2]}" ]]; then
  echo "build-opus-macos: up to date"
  exit 0
fi

mkdir -p "$SRC"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --sdk macosx -f clang)"

# 1. Fetch and verify the pinned tarballs.
for entry in "${PKGS[@]}"; do
  read -r name version url want <<<"$entry"
  file="$SRC/$name-$version.tar.gz"
  if [[ ! -f "$file" ]] || [[ "$(shasum -a 256 "$file" | cut -d' ' -f1)" != "$want" ]]; then
    rm -f "$file"
    curl -fsSL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  got="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  if [[ "$got" != "$want" ]]; then
    rm -f "$file"
    echo "build-opus-macos: SHA-256 mismatch for $name $version (got $got)" >&2
    exit 1
  fi
done

# 2. Build each architecture into its own prefix from a fresh extraction.
for arch in "${ARCHS[@]}"; do
  host="$([[ $arch == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)"
  prefix="$OUT/$arch"
  work="$SRC/build-$arch"
  rm -rf "$work" "$prefix"
  mkdir -p "$work" "$prefix"
  flags="-arch $arch -isysroot $SDK -mmacosx-version-min=$MIN -O2 -fPIC"
  export CC="$CLANG -arch $arch" CFLAGS="$flags" LDFLAGS="-arch $arch -isysroot $SDK -mmacosx-version-min=$MIN"
  common=(--host="$host" --prefix="$prefix" --disable-shared --enable-static)

  for entry in "${PKGS[@]}"; do
    read -r name version _ _ <<<"$entry"
    tar -xzf "$SRC/$name-$version.tar.gz" -C "$work"
  done

  (cd "$work/libogg-1.3.6" && ./configure "${common[@]}" >"$work/ogg.log" 2>&1 &&
     make -j"$JOBS" >>"$work/ogg.log" 2>&1 && make install >>"$work/ogg.log" 2>&1)

  (cd "$work/opus-1.5.2" && ./configure "${common[@]}" --disable-doc --disable-extra-programs \
     >"$work/opus.log" 2>&1 && make -j"$JOBS" >>"$work/opus.log" 2>&1 &&
     make install >>"$work/opus.log" 2>&1)

  # No pkg-config on the build machine: the DEPS_* variables short-circuit
  # PKG_CHECK_MODULES in opusfile's configure.ac.
  # opus installs its public headers under include/opus/ (as its .pc file says).
  (cd "$work/opusfile-0.12" && DEPS_CFLAGS="-I$prefix/include -I$prefix/include/opus" \
     DEPS_LIBS="-L$prefix/lib -lopus -logg" ./configure "${common[@]}" \
     --disable-http --disable-doc --disable-examples >"$work/opusfile.log" 2>&1 &&
     make -j"$JOBS" >>"$work/opusfile.log" 2>&1 && make install >>"$work/opusfile.log" 2>&1)
done

# 3. Combine into universal archives. Headers are identical across arches.
rm -rf "$OUT/lib" "$OUT/include"
mkdir -p "$OUT/lib"
cp -R "$OUT/arm64/include" "$OUT/include"
for lib in libogg libopus libopusfile; do
  lipo -create "$OUT/arm64/lib/$lib.a" "$OUT/x86_64/lib/$lib.a" -output "$OUT/lib/$lib.a"
done
printf '%s\n' "$STAMP_WANT" >"$OUT/stamp"
echo "build-opus-macos: built $OUT/lib (${ARCHS[*]}, min $MIN)"
