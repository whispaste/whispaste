# Building WhisPaste from source

This guide shows how to build the desktop app and its bundled on-device engines on macOS, Windows and Linux. Every command below is taken from the CI workflows (`.github/workflows/ci.yml`, `release.yml`, `headless-benchmark.yml`) and the scripts in `scripts/`. If this file and a workflow disagree, the workflow is the source of truth.

## What gets built

| Part | Source | Needed for |
|---|---|---|
| Flutter app | this repo | everything |
| `libwhisper` + ggml backends | [whisper.cpp](https://github.com/ggml-org/whisper.cpp) `v1.8.4` | on-device Whisper transcription |
| `libllama` + Smart Mode shim | [llama.cpp](https://github.com/ggml-org/llama.cpp) `b10150` + `native/smart_mode/` | on-device Smart Mode (optional) |

The app builds and runs without the native libraries. Cloud transcription and Parakeet (bundled through the `sherpa_onnx` package) work regardless. Without `libwhisper`, on-device Whisper is unavailable. Without `libllama`, the on-device Smart Mode option is disabled in Settings.

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

## Windows (x64)

**Toolchain:** Visual Studio 2022 with the "Desktop development with C++" workload (MSVC, Windows SDK), CMake, Ninja, PowerShell 7 (`pwsh`). For the Vulkan GPU backend, install the [Vulkan SDK](https://vulkan.lunarg.com/).

Build the app first. The staging scripts copy into its output folder.

```powershell
flutter build windows --release --no-tree-shake-icons
```

`libwhisper` (run from a Developer PowerShell for VS 2022, so `cl.exe` is on `PATH`):

```powershell
git clone --depth 1 --branch v1.8.4 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.8.4
cmake -S .build/deps/whisper.cpp/v1.8.4 -B .build/libwhisper/windows-build `
  -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON `
  -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON `
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF
cmake --build .build/libwhisper/windows-build --config Release -j
New-Item -ItemType Directory -Force -Path .build/libwhisper/windows | Out-Null
Copy-Item .build/libwhisper/windows-build/bin/*.dll .build/libwhisper/windows/ -Force
pwsh scripts/bundle-libwhisper-windows.ps1 -Source .build/libwhisper/windows
```

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
  libayatana-appindicator3-dev libasound2-dev \
  libcurl4-openssl-dev zlib1g-dev \
  libflac-dev libogg-dev libopus-dev libvorbis-dev \
  default-jdk \
  g++ patchelf libvulkan-dev glslang-tools glslc spirv-headers \
  xvfb
```

```bash
flutter build linux --release --no-tree-shake-icons
```

`libwhisper` (Vulkan + one CPU backend per x86-64 feature level via `-DGGML_CPU_ALL_VARIANTS=ON`, `$ORIGIN` rpath). The `libggml-cpu-*.so` modules must stay next to `libwhisper.so` in `bundle/lib/`, where the app tells ggml to look for them. Set `BUILD_JOBS=N` to cap parallelism on machines with little RAM:

```bash
git clone --depth 1 --branch v1.8.4 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.8.4
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

Run the bundle with `build/linux/x64/release/bundle/whispaste`.

## Checking a build

These commands need no UI and leave your settings alone:

```bash
whispaste --diagnose [--out report.json]    # do the bundled engine libraries load? exit 0 = ok
whispaste --transcribe-file clip.wav --json # transcribe a 16 kHz mono WAV with a downloaded model
```

On Windows, pass `--out` and redirect the output, because the GUI binary has no reliable console.

`scripts/smoke/` holds the package smoke tests that the release pipeline runs on every artifact before publishing:

- `smoke-macos.sh <dmg|app>`: signature, bundled dylib links, `--diagnose`
- `smoke-windows.ps1 -ArtifactDir <dir>`: silent install, `--diagnose`
- `smoke-linux.sh <artifact-dir>`: `.deb`/AppImage, `ldd`, `--diagnose` under Xvfb

They install packages, so run them in a VM or on a CI runner, not on your daily machine.

## Gate commands

Before opening a pull request, run the gates listed in [CONTRIBUTING.md](CONTRIBUTING.md#gate-commands). For an overview of the code, see [ARCHITECTURE.md](ARCHITECTURE.md).
