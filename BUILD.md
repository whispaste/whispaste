# Building WhisPaste from source

This guide shows how to build the desktop app and its bundled on-device engines on macOS, Windows and Linux. Every command below is taken from the CI workflows (`.github/workflows/ci.yml`, `release.yml`) and the scripts in `scripts/`. If this file and a workflow disagree, the workflow is the source of truth.

## What gets built

| Part | Source | Needed for |
|---|---|---|
| Flutter app | this repo | everything |
| `libwhisper` + ggml backends | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) `v1.9.5` | on-device Whisper transcription |
| `libparakeet` (GPU Parakeet, built from the same whisper.cpp tree) | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) `v1.9.5` (`src/parakeet.cpp`, `include/parakeet.h`, MIT) | GPU Parakeet on Metal, Vulkan or CUDA; sherpa-onnx CPU is the fallback |
| Parakeet GGUF model | [ggml-org/parakeet-GGUF](https://huggingface.co/ggml-org/parakeet-GGUF) at revision `35156454d1a39de06863303dd209fd2bed6ee079`, q8_0 | downloaded on demand with the Parakeet model; SHA-256 pinned in `parakeet_gguf_model.dart`. Licence MIT (conversion) of NVIDIA `parakeet-tdt-0.6b-v3`, CC-BY-4.0 |
| `libllama` + Smart Mode shim | [llama.cpp](https://github.com/ggml-org/llama.cpp) `b10150` + `native/smart_mode/` | on-device Smart Mode (optional) |
| `libsherpa-onnx-c-api` (no TTS) + onnxruntime | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) `v1.13.4` (commit `1428072`), built with `SHERPA_ONNX_ENABLE_TTS=OFF`; onnxruntime fetched and SHA-256 checked by sherpa's CMake | on-device Parakeet (CPU), voice activity detection. The shipped build contains no espeak-ng (GPL-3.0) and no piper-phonemize, see below |

The app builds and runs without the native libraries. Cloud transcription and Parakeet on the CPU (through the `sherpa_onnx` package) work regardless. Parakeet on the GPU needs `libparakeet` and the GGUF model; without them it falls back to sherpa-onnx. Without `libwhisper`, on-device Whisper is unavailable. Without `libllama`, the on-device Smart Mode option is disabled in Settings.

Pinned sources are cloned into `.build/deps/` and staged under `.build/libwhisper/<os>` and `.build/libllama/<os>`. `.build/` is gitignored. The build scripts check that the pinned commit is checked out and refuse to build anything else.

## Common prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) stable. CI pins **3.44.1**.
- Git and CMake on `PATH`.
- Then, in the repo root:

```bash
flutter pub get
```

## macOS (Apple Silicon)

**Toolchain:** Xcode with its command line tools, CMake.

```bash
flutter build macos --debug       # or: flutter run -d macos
```

Xcode build phases (`macos/embed_libwhisper.sh`, `macos/embed_libllama.sh`) build and embed `libwhisper` and `libllama` automatically when their staging directories are missing. `scripts/build-libwhisper-macos.sh` clones whisper.cpp itself. To build the libraries ahead of time (Metal + CPU backends):

```bash
bash scripts/build-libwhisper-macos.sh

git clone --depth 1 --branch b10150 https://github.com/ggml-org/llama.cpp .build/deps/llama.cpp/b10150
bash scripts/build-libllama-macos.sh
bash scripts/build-smartmode-shim-macos.sh
```

Both scripts build with `-DGGML_NATIVE=OFF`, so the libraries never contain instructions the oldest supported Mac (M1) lacks. `libwhisper` additionally uses `-DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON`: Metal and one CPU module per Apple Silicon generation (`libggml-cpu-apple_m1.so`, `-apple_m2_m3.so`, `-apple_m4.so`) are staged next to `libwhisper.dylib`, and ggml loads the best CPU module at runtime. `macos/embed_libwhisper.sh` rebuilds automatically when the staged `WHISPER_PIN` no longer matches the pinned whisper.cpp version.

## sherpa-onnx without TTS (all desktop platforms)

The `sherpa_onnx` pub package ships prebuilt C-API libraries that link espeak-ng
(GPL-3.0-or-later) through the text-to-speech frontends. WhisPaste is MIT and uses
no TTS, so the app bundles its own build from the pinned tag with TTS off, instead.
The Dart bindings stay the pub package's.

```bash
bash scripts/build-sherpa-onnx.sh macos              # universal arm64 + x86_64, about 6 min
bash scripts/build-sherpa-onnx.sh linux              # x86_64
bash scripts/build-sherpa-onnx.sh linux --toolchain <aarch64 toolchain> --stage-name linux-aarch64
```

```powershell
pwsh -File scripts\build-sherpa-onnx.ps1            # Windows x64
powershell -File scripts\build-sherpa-onnx.ps1      # same, Windows PowerShell 5.1
```

Output goes to `.build/sherpa-onnx/<platform>/`. The macOS Xcode phase
`[WP] Embed sherpa-onnx (no TTS)` (`macos/embed_sherpa_onnx.sh`) replaces the pub
dylib in the app bundle before signing and builds the staging dir itself on a
local build. Linux and Windows CMake (`linux/CMakeLists.txt`,
`windows/CMakeLists.txt`) swap the bundled libraries the same way.

Release guard: `scripts/check-no-espeak.sh <path>...` fails on any native binary
that carries espeak-ng or piper markers, or a file named after them, and (ELF and
Mach-O via `nm`, PE via `objdump` when installed) on an exported or imported
symbol named espeak or piper. A native file whose symbols cannot be read fails.
It runs on each platform bundle, on the GPU-probe engine folder (`make-dist.ps1`),
and its negative test is `scripts/check-no-espeak.test.sh`.

Limits of the guard: both checks are name-based. Code compiled in without any
symbol or string naming espeak or piper is not detected, and the pub original
exports no espeak symbol at all (only its strings carry the names), so the byte
markers are what catches it. The control for the rest is the build itself:
`-DSHERPA_ONNX_ENABLE_TTS=OFF` plus the stage check below.

Supply-chain controls (WP-57 security review):

- **Pins**: `scripts/sherpa-onnx.pin` holds the sherpa-onnx tag and commit, the
  onnxruntime archive names and their SHA-256. The build asserts that sherpa's own
  `cmake/onnxruntime-*.cmake` pins the same hash.
- **onnxruntime**: `scripts/fetch-onnxruntime.sh` (and the Windows script) download
  the archive and verify SHA-256 before cmake runs. cmake only sees the verified
  local file, so it never downloads an unverified archive.
- **Stage check**: `scripts/check-sherpa-stage.cmake` runs in every consumer (the
  macOS embed phase, Linux and Windows CMake, `release.yml` after the cache restore,
  the Windows build script and the GPU-probe packaging). It requires `BUILD_INFO`
  to name the pinned tag and commit, the tag version to equal the `sherpa_onnx`
  version in `pubspec.lock`, and the SHA-256 of every staged file to match the value
  recorded at build time. Test: `scripts/check-sherpa-stage.test.sh`.
- **Reference hashes (GS-013)**: `SHERPA_C_API_SHA256_<PLATFORM>` in
  `scripts/sherpa-onnx.pin` are reference values only. A mismatch is a warning from
  the stage check, not a release gate (see residual risk below). They are empty.

Limit of the stage check: `BUILD_INFO` lives in the same cache as the libraries, so
a writer of that cache can rewrite both. The release job therefore re-checks the
staged files after the cache restore, and the guard runs on the final bundle.

### Residual risk GS-013: native library is not bit-reproducible across checkouts

Decision: proposed 2026-10-17, pending the maintainer's acceptance. Owner: Silvio Lindstedt (maintainer).
Review date: 2026-11-17, or earlier before the next sherpa-onnx bump.

Facts, measured on macOS with the same tag, commit, onnxruntime archive and SDK:

- Same checkout path, two clean rebuilds: identical library and identical object
  file (`e1faf847…`), so the build is deterministic per path.
- Two checkout paths: `e1faf847…` and `13021ca1…`. The difference is not in the
  machine code (disassembly identical). It sits in the ThinLTO bitcode objects
  (`-flto=thin`), which embed the object path. `-ffile-prefix-map` maps `__FILE__`
  and debug paths, but not that path. The shipped library contains no absolute path.
- The CI runner image, Xcode and SDK versions are not pinned, so even a fixed path
  would not prove a rebuild gives the same hash.

Consequence: a hash pin fails whenever the checkout path changes, so it cannot be a
release gate. Release builds are not gated on a hash.

Replacement controls:

1. Source identity: the build aborts if the checkout is not at `SHERPA_COMMIT`
   (`scripts/build-sherpa-onnx.sh`), and the stage check compares `BUILD_INFO`
   with the pin and with `pubspec.lock`.
2. onnxruntime identity: the archive SHA-256 is verified before cmake runs
   (`scripts/fetch-onnxruntime.sh`, GS-008).
3. Staged-file integrity: per-file SHA-256 in `BUILD_INFO`, rechecked after the
   cache restore in `release.yml`.
4. Bundle integrity: Developer-ID signing with `--deep --force`, notarization,
   `stapler validate`, `spctl --assess`, and `codesign --verify --deep --strict` on
   the `.app` (`release.yml`). The embedded `libsherpa-onnx-c-api.dylib` is sealed
   in `CodeResources` after the deep re-sign (checked locally on an ad-hoc copy).
5. Update channel: installers carry an EdDSA signature (Sparkle, `sign_update`).

Not covered: the link between the shipped binary and the exact source. Only
the controls above, which show who built it from which pinned inputs.

Measured values for the record (macOS, arm64+x86_64 universal, 2026-10-17):
`e1faf8474287cf5d237004f47082722f8e479f09695e5021661c266b064d7087` (checkout A,
the worktree used for the release branch),
`13021ca17a7ad9159b5b5003890b51ead35b501352c61567ffba0403896d26e7` (checkout B,
a copy in another directory).

Verified by probe builds (sherpa-onnx `v1.13.4`, TTS off): macOS universal (6.0 MB),
Linux x64 (3.6 MB), Windows x64 (3.2 MB, `onnxruntime_providers_shared.dll` not
needed) and Linux aarch64 (3.1 MB, cross build; not shipped, because release.yml
builds x86_64 only). Each exports the same 172 `SherpaOnnx*` symbols as the pub
original and gives identical recognition output with the parakeet-tdt-0.6b-v3 model.

## Third-party notices

`THIRD_PARTY_NOTICES.md` is generated: `python3 scripts/generate-third-party-notices.py`
(`--check` fails when it is stale; `flutter test test/core/licenses/` runs that check).

## Windows (x64)

**Toolchain:** Visual Studio 2022 with the "Desktop development with C++" workload (MSVC, Windows SDK), CMake, Ninja, PowerShell 7 (`pwsh`). For the Vulkan GPU backend, install the [Vulkan SDK](https://vulkan.lunarg.com/).

Build the app first. The staging scripts copy into its output folder.

```powershell
flutter build windows --release --no-tree-shake-icons
```

`libwhisper` (run from a Developer PowerShell for VS 2022, so `cl.exe` is on `PATH`):

```powershell
git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.9.5
cmake -S .build/deps/whisper.cpp/v1.9.5 -B .build/libwhisper/windows-build `
  -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON `
  -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON `
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
cmake --build .build/libwhisper/windows-build --config Release -j
cmake -S native/ffi_guard -B .build/libwhisper/windows-build/ffi_guard -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DWHISPER_SOURCE_DIR="$PWD/.build/deps/whisper.cpp/v1.9.5"
cmake --build .build/libwhisper/windows-build/ffi_guard --config Release
New-Item -ItemType Directory -Force -Path .build/libwhisper/windows | Out-Null
Copy-Item .build/libwhisper/windows-build/bin/*.dll .build/libwhisper/windows/ -Force
Copy-Item .build/libwhisper/windows-build/ffi_guard/wp_ffi_guard.dll .build/libwhisper/windows/ -Force
pwsh scripts/bundle-libwhisper-windows.ps1 -Source .build/libwhisper/windows
```

`wp_ffi_guard` (`native/ffi_guard`) wraps the whisper and sherpa-onnx calls that can throw C++ exceptions, so an exception from ggml-vulkan or ONNX Runtime becomes a normal error instead of aborting the app. The macOS and Linux build scripts build it alongside `libwhisper`; the Windows bundle script refuses a build without it.

`-DGGML_CPU_ALL_VARIANTS=ON` builds one `ggml-cpu-<level>.dll` per x86-64 feature level (x64, sse42, sandybridge, haswell, skylakex, icelake, alderlake, …); ggml loads the best one the CPU supports at runtime. The bundle script refuses a build without them. `whispaste --diagnose` reports the variant it picked (`cpuBackend`).

`libllama` and the Smart Mode shim (optional):

```powershell
git clone --depth 1 --branch b10150 https://github.com/ggml-org/llama.cpp .build/deps/llama.cpp/b10150
pwsh scripts/build-libllama-windows.ps1
pwsh scripts/build-smartmode-shim-windows.ps1
pwsh scripts/bundle-libllama-windows.ps1 -Source .build/libllama/windows
```

The result is in `build\windows\x64\runner\Release\` (`whispaste.exe`, `whisper.dll`, `smart_mode\smartmode_shim.dll`).

## Linux (x86_64)

**Toolchain:** the packages the release job installs on Ubuntu:

```bash
sudo apt-get install -y \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libsecret-1-dev \
  libkeybinder-3.0-dev libnotify-dev \
  libayatana-appindicator3-dev libasound2-dev libxss-dev \
  libcurl4-openssl-dev zlib1g-dev \
  libflac-dev libogg-dev libopus-dev libopusfile-dev libvorbis-dev \
  default-jdk \
  g++ patchelf libvulkan-dev glslang-tools glslc spirv-headers \
  xvfb
```

```bash
flutter build linux --release --no-tree-shake-icons
```

`libwhisper` (Vulkan + one CPU backend per x86-64 feature level via `-DGGML_CPU_ALL_VARIANTS=ON`, `$ORIGIN` rpath). The `libggml-cpu-*.so` modules must stay next to `libwhisper.so` in `bundle/lib/`, where the app tells ggml to look for them. Set `BUILD_JOBS=N` to cap parallelism on machines with little RAM:

```bash
git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.9.5
bash scripts/build-libwhisper-linux.sh
mkdir -p build/linux/x64/release/bundle/lib
cp .build/libwhisper/linux/*.so* build/linux/x64/release/bundle/lib/
```

`libllama` and the Smart Mode shim (optional):

```bash
git clone --depth 1 --branch b10150 https://github.com/ggml-org/llama.cpp .build/deps/llama.cpp/b10150
bash scripts/build-libllama-linux.sh
mkdir -p build/linux/x64/release/bundle/lib/smart_mode
cp .build/libllama/linux/*.so* build/linux/x64/release/bundle/lib/smart_mode/
```

Optional, experimental CUDA backend for NVIDIA GPUs (not shipped in any package yet): `--cuda` builds only `libggml-cuda.so` plus the CUDA runtime it links (cudart, cuBLAS, cuBLASLt) into `.build/libwhisper/linux-cuda/`. It needs `nvcc` (e.g. via `python3 scripts/fetch-cuda-redist.py 12.8.1 linux-x86_64 <dir>`, then set `CUDA_HOME=<dir>` and put `<dir>/bin` on `PATH`). Copied into `bundle/lib/`, ggml prefers it over Vulkan; `whispaste --transcribe-file <wav> --json` reports the device in `gpuDevice` (`CUDA0`). CI does not build it. `tool/vast_cuda_bench.sh` builds it on a rented NVIDIA box, orchestrated from the Mac without GitHub.

```bash
bash scripts/build-libwhisper-linux.sh --cuda
```

Run the bundle with `build/linux/x64/release/bundle/whispaste`.

## Checking a build

These commands need no UI and leave your settings alone:

```bash
whispaste --diagnose [--out report.json]    # do the bundled engine libraries load? exit 0 = ok
whispaste --transcribe-file clip.wav --json # transcribe a 16 kHz mono WAV with a downloaded model
```

On Windows, pass `--out` and redirect the output, because the GUI binary has no reliable console.

On macOS and Windows there is no display-less mode, so run `--diagnose` in a desktop session. On Windows the main window appears during the check: it is shown on the first frame unless the app starts with `--autostart`.

On Linux, `--diagnose` also runs without `DISPLAY`/`WAYLAND_DISPLAY` (SSH, CI). Flutter starts Dart only after GTK opened a display, so the runner starts a private `Xvfb -displayfd` for the check (10 s start timeout), and Xvfb ends with the app, even on a crash or signal. Without Xvfb in `PATH`, and always inside Flatpak or Snap, it writes `{"ok": false, "error": …}` instead and exits 2; run it under `xvfb-run` there. Normal starts are unchanged. The decision logic is unit-tested by `test/scripts/diagnose_launch_test.sh`.

`scripts/smoke/` holds the package smoke tests that the release pipeline runs on every artifact before publishing:

- `smoke-macos.sh <dmg|app>`: signature, bundled dylib links, `--diagnose`
- `smoke-windows.ps1 -ArtifactDir <dir>`: silent install, `--diagnose`
- `smoke-linux.sh <artifact-dir>`: `.deb`/AppImage, `ldd`, `--diagnose` under Xvfb

They install packages, so run them in a VM or on a CI runner, not on your daily machine.

## Gate commands

Before opening a pull request, run the gates listed in [CONTRIBUTING.md](CONTRIBUTING.md#gate-commands). For an overview of the code, see [ARCHITECTURE.md](ARCHITECTURE.md).
