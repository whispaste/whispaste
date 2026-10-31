# Building WhisPaste from source

This guide shows how to build the desktop app and its bundled on-device engines on macOS, Windows and Linux. Every command below is taken from the scripts in `scripts/`.

## What gets built

| Part | Source | Needed for |
|---|---|---|
| Flutter app | this repo | everything |
| `libwhisper` + ggml backends | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), tag in `scripts/whisper-cpp.pin` | on-device Whisper transcription |
| `libparakeet` (GPU Parakeet, built from the same whisper.cpp tree) | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), tag in `scripts/whisper-cpp.pin` (`src/parakeet.cpp`, `include/parakeet.h`, MIT) | GPU Parakeet on Metal, Vulkan or CUDA; sherpa-onnx CPU is the fallback |
| Parakeet GGUF model | [ggml-org/parakeet-GGUF](https://huggingface.co/ggml-org/parakeet-GGUF) at revision `35156454d1a39de06863303dd209fd2bed6ee079`, q8_0 | downloaded on demand with the Parakeet model; SHA-256 pinned in `parakeet_gguf_model.dart`. Licence MIT (conversion) of NVIDIA `parakeet-tdt-0.6b-v3`, CC-BY-4.0 |
| `libllama` + Smart Mode shim | [llama.cpp](https://github.com/ggml-org/llama.cpp), tag in `scripts/llama-cpp.pin` + `native/smart_mode/` | on-device Smart Mode (optional) |
| `libsherpa-onnx-c-api` (no TTS) + onnxruntime | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) `v2.0.1` (commit `af2d8d8`), built with `SHERPA_ONNX_ENABLE_TTS=OFF`; onnxruntime fetched and SHA-256 checked by sherpa's CMake | on-device Parakeet (CPU), voice activity detection. The shipped build contains no espeak-ng (GPL-3.0) and no piper-phonemize, see below |

The app builds and runs without the native libraries. Cloud transcription and Parakeet on the CPU (through the `sherpa_onnx` package) work regardless. Parakeet on the GPU needs `libparakeet` and the GGUF model; without them it falls back to sherpa-onnx. Without `libwhisper`, on-device Whisper is unavailable. Without `libllama`, the on-device Smart Mode option is disabled in Settings.

Pinned sources live in `.build/deps/<lib>/<tag>` and are staged under `.build/libwhisper/<os>` and `.build/libllama/<os>`. `.build/` is gitignored. `scripts/fetch-native-deps.sh [whisper|llama|sherpa]` clones a pinned tag, checks its commit against the pin and only then moves it into place; a tree at another commit is refused and left alone, and a lock keeps two builds in one checkout from fetching at once. The macOS and Linux build scripts call it themselves and refuse to build anything but the pinned commit.

## Common prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) stable. CI pins **3.47.9**.
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

Xcode build phases (`macos/embed_libwhisper.sh`, `macos/embed_libllama.sh`) build and embed `libwhisper` and `libllama` automatically when their staging directories are missing. The build scripts fetch their pinned sources themselves. To build the libraries ahead of time (Metal + CPU backends):

```bash
bash scripts/build-libwhisper-macos.sh
bash scripts/build-libllama-macos.sh
bash scripts/build-smartmode-shim-macos.sh
```

Both scripts build with `-DGGML_NATIVE=OFF`, so the libraries never contain instructions the oldest supported Mac (M1) lacks. `libwhisper` additionally uses `-DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON`: Metal and one CPU module per Apple Silicon generation (`libggml-cpu-apple_m1.so`, `-apple_m2_m3.so`, `-apple_m4.so`) are staged next to `libwhisper.dylib`, and ggml loads the best CPU module at runtime. `macos/embed_libwhisper.sh` rebuilds automatically when the staged `WHISPER_PIN` no longer matches the pinned whisper.cpp version.

### Bundle identifiers

| Build | Bundle ID |
|---|---|
| Debug and Profile (`flutter run`, `flutter build macos --debug/--profile`) | `de.whispaste.direct.dev` |
| The copy the macOS smoke test starts | `de.whispaste.direct.smoke` |
| Developer-ID release (DMG, Homebrew) | `de.whispaste.direct` |
| Mac App Store | `de.whispaste.app` |

macOS binds privacy grants (Accessibility, Input Monitoring, Microphone) and preferences to the bundle ID. A local build therefore never shares them with an installed release, and resetting its own stale Accessibility entry cannot clear the release's grant. Only the Developer-ID release adopts the state of the older `de.whispaste.app` identity (`BundleIdMigrationHost.adoptLegacyIdentityIfNeeded`). The data folder `~/Library/Application Support/WhisPaste` does not depend on the bundle ID.

Preferences live in the real `~/Library/Preferences` even when `HOME` points elsewhere, so the smoke has an ID of its own: a run with the preview's ID left its settings in the preview. After every run the smoke removes the smoke ID's preferences, caches, saved state and privacy grants.

LaunchServices keeps a registration for every `.app` macOS has seen (a build, `open`, Finder), and it outlives the folder. System Settings then resolves the bundle ID to a dead path: dragging the app into Accessibility does nothing. Before a `build/` folder goes away, unregister its apps from LaunchServices first (`lsregister -u <app>`).

### Swift unit tests

The pure Swift logic of the macOS runner (paste key per keyboard layout, where the accessibility helper panel goes) has XCTest cases in `macos/RunnerTests/`. Run them on the Mac before merging a change to `macos/Runner/`, after one `flutter build macos --debug`:

```bash
cd macos && nice -n 19 xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -only-testing:RunnerTests -derivedDataPath ../build/macos
```

Delete `build/` afterwards.

### macOS plugin files

`macos/Flutter/GeneratedPluginRegistrant.swift` and `macos/Podfile.lock` are generated, but committed: the Mac build links exactly the plugins they name. They follow from `pubspec.lock`, `macos/Podfile` and the Flutter SDK in `.flutter-version`. Nobody edits them by hand:

```bash
bash scripts/sync-macos-plugins.sh          # macOS: pub get + pod install, both files rewritten
```

- **Commit:** when `pubspec.yaml`, `pubspec.lock`, `.flutter-version`, `macos/Podfile` or `macos/.cocoapods-version` is in a commit, the pre-commit hook runs the sync on the Mac and stages both files into the same commit (only these two). It never blocks the commit. If the sync fails or takes longer than 120 s (offline, no CocoaPods, a stale spec repo, another sync holding the lock), the hook prints a warning and the fix command. Commits without these inputs do not touch pod.
- **Push:** the pre-push hook compares the plugin names in both committed files with the macOS plugins `flutter pub get` resolved (`dart tool/macos_plugins.dart`, under a second). Real drift blocks on the Mac (after one more `flutter pub get`, in case the resolved list predates the last checkout) and only warns elsewhere. A check that cannot tell (no `pub get` yet, uncommitted pubspec changes) never blocks. Version-only changes are not part of this check: the commit hook takes them in with the pubspec change.
- **No noise:** git clean filters normalize what is not a real change. `mas-guard` restores the `#if !MAS_BUILD` guard around the auto-updater, which every `flutter pub get/analyze/test` drops; a Mac App Store build without it crashes at launch. `podlock` pins the `COCOAPODS:` line to `macos/.cocoapods-version`, so another local CocoaPods version is no change. `scripts/install-git-filters.sh` sets both filters; the hooks and the sync call it.
- `pod install` runs without `--repo-update`. Pods that only `Podfile.lock` pins (Sparkle) keep their version; raise them with `cd macos && pod update <pod>`, then run the sync. To move to a new CocoaPods, change `macos/.cocoapods-version`.

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

Output goes to `.build/sherpa-onnx/<platform>/`. After a bump in
`scripts/sherpa-onnx.pin` the build directory (`<platform>-build/`) still holds
the old tag's CMake cache; both scripts notice that and start it fresh, so a
re-run is all a bump needs. The macOS Xcode phase
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

Supply-chain controls:

- **Pins**: `scripts/sherpa-onnx.pin` holds the sherpa-onnx tag and commit, the
  onnxruntime archive names and their SHA-256. The build asserts that sherpa's own
  `cmake/onnxruntime-*.cmake` pins the same hash.
- **onnxruntime**: `scripts/fetch-onnxruntime.sh` (and the Windows script) download
  the archive and verify SHA-256 before cmake runs. cmake only sees the verified
  local file, so it never downloads an unverified archive.
- **Stage check**: `scripts/check-sherpa-stage.cmake` runs in every consumer (the
  macOS embed phase, Linux and Windows CMake, the release pipeline after the cache restore,
  the Windows build script and the GPU-probe packaging). It requires `BUILD_INFO`
  to name the pinned tag and commit, the tag version to equal the `sherpa_onnx`
  version in `pubspec.lock`, and the SHA-256 of every staged file to match the value
  recorded at build time. Test: `scripts/check-sherpa-stage.test.sh`.
- **Reference hashes**: `SHERPA_C_API_SHA256_<PLATFORM>` in
  `scripts/sherpa-onnx.pin` are reference values only. A mismatch is a warning from
  the stage check, not a release gate (see residual risk below). They are empty.

Limit of the stage check: `BUILD_INFO` lives in the same cache as the libraries, so
a writer of that cache can rewrite both. The release job therefore re-checks the
staged files after the cache restore, and the guard runs on the final bundle.

### Residual risk: native library is not bit-reproducible across checkouts


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
   (`scripts/fetch-onnxruntime.sh`).
3. Staged-file integrity: per-file SHA-256 in `BUILD_INFO`, rechecked after the
   cache restore in the release pipeline.
4. Bundle integrity: Developer-ID signing with `--deep --force`, notarization,
   `stapler validate`, `spctl --assess`, and `codesign --verify --deep --strict` on
   the `.app` (release pipeline). The embedded `libsherpa-onnx-c-api.dylib` is sealed
   in `CodeResources` after the deep re-sign (checked locally on an ad-hoc copy).
5. Update channel: installers carry an EdDSA signature (Sparkle, `sign_update`).

Not covered: the link between the shipped binary and the exact source. Only
the controls above, which show who built it from which pinned inputs.

Measured values for the record (macOS, arm64+x86_64 universal, 2026-10-17):
`e1faf8474287cf5d237004f47082722f8e479f09695e5021661c266b064d7087` (checkout A,
the worktree used for the release branch),
`13021ca17a7ad9159b5b5003890b51ead35b501352c61567ffba0403896d26e7` (checkout B,
a copy in another directory).

Verified by probe builds (sherpa-onnx `v2.0.1`, TTS off): macOS universal (6.8 MB),
Linux x64 (4.1 MB) and Windows x64 (3.3 MB, `onnxruntime_providers_shared.dll` not
needed). macOS and Linux export 178 `SherpaOnnx*` symbols; Parakeet
(parakeet-tdt-0.6b-v3) recognises the same test sentence at normal level and down
to -60 dB on all three. Linux aarch64 is a cross build and not shipped
(the release builds x86_64 only). Since 2.0 the pub original contains no espeak-ng
either; on macOS it links onnxruntime statically (58 MB). Whether to keep the own
build is an open decision.

## Raising native dependencies

whisper.cpp, sherpa-onnx and llama.cpp each have one pin: `scripts/whisper-cpp.pin` (tag + commit), `scripts/sherpa-onnx.pin` and `scripts/llama-cpp.pin` (tag + commit). Every build script, `scripts/ensure-libllama-macos.sh`, `scripts/release-macos-local.sh` and the release workflow read the tag from there; nothing else names the version.

Current versions are the default. `scripts/check-upstream-pins.sh` compares all three pins with the newest stable GitHub release (pre-releases ignored; answer cached 24 h in the git dir, offline = skipped, under 2 s):

- Before a release `scripts/check-upstream-pins.sh --strict` must pass. It fails while a pin is older than upstream, unless the `.pin` file documents a hold: `UPSTREAM_HOLD_REASON` (why) and `UPSTREAM_HOLD_CHECK` (what lifts it), both filled.
- Build tags of the same scheme compare by number (`b10150` < `b10200`). A pin of another scheme than upstream's latest release (llama.cpp `b10150` against `v0.8.0`, after upstream switched to stable `v0.x` releases) cannot be ordered and is always reported, never passed silently.
- Logic test without network: `bash scripts/check-upstream-pins.test.sh`.

Raising one, as its own work package:

1. Change tag and commit in the `.pin` file (sherpa-onnx: also `sherpa_onnx` in `pubspec.yaml`/`pubspec.lock` and the onnxruntime hashes, see above). Clear a hold that no longer applies.
2. Build locally on all three platforms: macOS (`scripts/build-libwhisper-macos.sh`, `scripts/build-sherpa-onnx.sh`, `scripts/build-libllama-macos.sh`), Linux, Windows (`scripts/build-libwhisper-windows.ps1`, `scripts/build-sherpa-onnx.ps1`, `scripts/build-libllama-windows.ps1`).
3. Engine tests on Linux and Windows, plus one real dictation per platform.
4. CHANGELOG entry naming the new upstream version and anything users notice.

The CUDA packs (`scripts/build-cuda-pack-*.{sh,ps1}`) read `scripts/whisper-cpp.pin` too, but carry the whisper.cpp version in their pack id and move with their own pack revision: both scripts stop when the pack id does not name the pinned tag.

## Third-party notices

`THIRD_PARTY_NOTICES.md` is generated: `python3 scripts/generate-third-party-notices.py`
(`--check` fails when it is stale; `flutter test test/core/licenses/` runs that check).

## Windows (x64)

**Toolchain:** Visual Studio 2022 with the "Desktop development with C++" workload (MSVC, Windows SDK), CMake, Ninja, PowerShell 7 (`pwsh`). For the Vulkan GPU backend, install the [Vulkan SDK](https://vulkan.lunarg.com/).

Build the app first. The staging scripts copy into its output folder.

```powershell
flutter build windows --release --no-tree-shake-icons
```

`libwhisper` (Vulkan + one CPU backend per x86-64 feature level, plus `wp_ffi_guard`). The script uses the same pin and cmake options as the release workflow. It needs the Vulkan SDK (`VULKAN_SDK`, `glslc.exe`) and activates the VS 2022 build tools itself when `cl.exe` is not on `PATH`:

```powershell
$tag = (Select-String '^WHISPER_TAG=(.*)' scripts/whisper-cpp.pin).Matches[0].Groups[1].Value
git clone --depth 1 --branch $tag https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/$tag
pwsh scripts/build-libwhisper-windows.ps1
pwsh scripts/bundle-libwhisper-windows.ps1 -Source .build/libwhisper/windows
```

`wp_ffi_guard` (`native/ffi_guard`) wraps the whisper and sherpa-onnx calls that can throw C++ exceptions, so an exception from ggml-vulkan or ONNX Runtime becomes a normal error instead of aborting the app. The macOS and Linux build scripts build it alongside `libwhisper`; the Windows bundle script refuses a build without it.

`-DGGML_CPU_ALL_VARIANTS=ON` builds one `ggml-cpu-<level>.dll` per x86-64 feature level (x64, sse42, sandybridge, haswell, skylakex, icelake, alderlake, …); ggml loads the best one the CPU supports at runtime. The bundle script refuses a build without them. `whispaste --diagnose` reports the variant it picked (`cpuBackend`).

`libllama` and the Smart Mode shim (optional):

```powershell
$tag = (Select-String '^LLAMA_TAG=(.*)' scripts/llama-cpp.pin).Matches[0].Groups[1].Value
git clone --depth 1 --branch $tag https://github.com/ggml-org/llama.cpp .build/deps/llama.cpp/$tag
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
bash scripts/build-libwhisper-linux.sh
mkdir -p build/linux/x64/release/bundle/lib
cp .build/libwhisper/linux/*.so* build/linux/x64/release/bundle/lib/
```

`libllama` and the Smart Mode shim (optional):

```bash
bash scripts/build-libllama-linux.sh
mkdir -p build/linux/x64/release/bundle/lib/smart_mode
cp .build/libllama/linux/*.so* build/linux/x64/release/bundle/lib/smart_mode/
```

Optional, experimental CUDA backend for NVIDIA GPUs (not shipped in any package yet): `--cuda` builds only `libggml-cuda.so` plus the CUDA runtime it links (cudart, cuBLAS, cuBLASLt) into `.build/libwhisper/linux-cuda/`. It needs `nvcc` (e.g. via `python3 scripts/fetch-cuda-redist.py 12.8.1 linux-x86_64 <dir>`, then set `CUDA_HOME=<dir>` and put `<dir>/bin` on `PATH`). Copied into `bundle/lib/`, ggml prefers it over Vulkan; `whispaste --transcribe-file <wav> --json` reports the device in `gpuDevice` (`CUDA0`). CI does not build it.

```bash
bash scripts/build-libwhisper-linux.sh --cuda
```

Run the bundle with `build/linux/x64/release/bundle/whispaste`.

Secondary windows (floating overlay, floating button, quick-paste panel, snippet picker) run their Flutter engines with Skia, the main window with the engine default (Impeller). With Flutter 3.47.9 an Impeller secondary window under Xwayland on a software-rendered GPU shows up but stays empty. The switch sits in `linux/runner/secondary_engine.cc`, together with the criterion for lifting it. A secondary window that draws no frame within 8 s logs a warning with its name.

### Packaging manifests

`bash scripts/ci/packaging-validate.sh [check...]` validates the manifests under `packaging/` (Scoop, Homebrew, Flatpak, AppImage/.deb, Snap, GNOME Shell extension) in a few seconds. It is the one definition: the `packaging-validate` workflow runs it, and the pre-push hook runs it on the lab's Ubuntu guest whenever a push touches one of its inputs (`--inputs` lists them; the workflow's push filter must list the same paths, which `scripts/check-workflow-hygiene.sh` checks). On the Mac, `scoop homebrew flatpak snap` run directly; `appimage-deb` and `gnome-extension` build a `.deb` with Linux `install(1)` and need the guest. `--install-deps` installs missing validators with apt. winget validation needs Windows and stays in the workflow.

## Local builds keep their own data

Debug and Profile builds (`flutter run`, `flutter build <platform> --debug` or `--profile`) are local builds. They never touch the data of an installed release:

| | Release | Local build |
|---|---|---|
| Data folder (history database, settings file, models, logs, single-instance lock) | `%APPDATA%\WhisPaste`, `~/Library/Application Support/WhisPaste`, `~/.config/whispaste` | `WhisPaste Dev` or `whispaste-dev` next to it |
| Capture folder | `%LOCALAPPDATA%\WhisPaste\capture`, `$XDG_RUNTIME_DIR/whispaste` | `WhisPaste Dev\capture`, `whispaste-dev` |
| Autostart entry (Windows Run key, Linux autostart file) | `WhisPaste` | `WhisPaste Dev` |
| Linux application ID (desktop entry, portal registration) | `de.whispaste.app` | `de.whispaste.app.dev` |

On macOS, the bundle ID separates privacy grants and preferences as well (see [Bundle identifiers](#bundle-identifiers)). A local build therefore starts empty: download a model in the app, or copy one by hand from the release folder's `models/`. Because the single-instance lock lives in the data folder, a local build and an installed release can run at the same time. Their global hotkeys then compete, so give the local build another one. The switch is `isLocalBuild` in `packages/whispaste_diagnostics` (`!dart.vm.product`), and `test/services/local_build_data_test.dart` keeps it in place.

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

They install packages, so run them in a VM or on a CI runner, not on your daily machine. The macOS smoke test runs locally on the Mac.

## Gate commands

Before opening a pull request, run the gates listed in [CONTRIBUTING.md](CONTRIBUTING.md#gate-commands). For an overview of the code, see [ARCHITECTURE.md](ARCHITECTURE.md).

### Local checks

`scripts/check.sh` is the one entry point; it runs the commands CI runs:

| Tier | Runs | Used by |
|---|---|---|
| `commit` | repo gates (`scripts/ci-gates.sh`), `dart format`, `flutter analyze` with CI's scope | by hand |
| `push [<range>]` | repo gates + the tests the range can break | by hand |
| `tests [<range>]` | only those tests | per pushed branch |
| `full` | the complete suite, plus the platform-branching files on Windows | integration round, before a release |

The default range is `origin/dev...HEAD`. `tool/affected_tests.dart` picks the tests: changed tests, tests that import a changed Dart file (also transitively), and guard tests that read a changed path, e.g. a guard over `scripts/whisper-cpp.pin`. Generated localizations (`lib/core/l10n/generated/`) pass nothing on through imports, since nearly every widget test imports them; the l10n and manual guards cover them. A range of only docs, `website/` or Markdown runs no Flutter tests; the website has its own gate.

