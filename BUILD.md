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

**Toolchain:** Xcode with its command line tools, CMake. Rust is only needed when Cargokit falls back to a source build: `cargokit_options.yaml` in the repo root sets `use_precompiled_binaries: true`, so `super_native_extensions` takes its signed prebuilt library even when `rustup` is installed (#674). For a source build use Rust stable **1.99.1 or newer** (`rustup update stable`).

With Xcode 27.2 and an older Rust, a fresh source build fails with `error[E0463]: can't find crate for proc_macro_error_attr`. Xcode exports `MACOSX_DEPLOYMENT_TARGET=13.0`, which also applies to host proc-macros, and from 12.0 on its linker writes chained fixups that rustc before 1.99 cannot read. A warm build directory hides the problem, so only a fresh build counts as a check.

```bash
flutter build macos --debug       # or: flutter run -d macos
```

Xcode build phases (`macos/embed_libwhisper.sh`, `macos/embed_libllama.sh`) build and embed `libwhisper` and `libllama` automatically when their staging directories are missing. The build scripts fetch their pinned sources themselves. To build the libraries ahead of time (Metal + CPU backends):

```bash
bash scripts/build-libwhisper-macos.sh
bash scripts/build-libllama-macos.sh
bash scripts/build-smartmode-shim-macos.sh
```

Both scripts build with `-DGGML_NATIVE=OFF`, so the libraries never contain instructions the oldest supported Mac (M1) lacks. They also pin the macOS floor to 13.0, the app's `MACOSX_DEPLOYMENT_TARGET` (#1740): run outside Xcode, CMake would otherwise take the SDK version and the libraries would not load on older systems. The floor is part of the stage stamps (`WHISPER_PIN` ends in `+macos:13.0`, libllama's `BUILD_FLAVOR` is `native-off macos13.0`), so an older stage is rebuilt. `libwhisper` additionally uses `-DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON`: Metal and one CPU module per Apple Silicon generation (`libggml-cpu-apple_m1.so`, `-apple_m2_m3.so`, `-apple_m4.so`) are staged next to `libwhisper.dylib`, and ggml loads the best CPU module at runtime. `macos/embed_libwhisper.sh` rebuilds automatically when the staged `WHISPER_PIN` no longer matches the pinned whisper.cpp version.

`libllama` is stamped the same way: `build-libllama-macos.sh` writes `LLAMA_PIN` (tag and commit) into the stage, and `macos/embed_libllama.sh` and `scripts/ensure-libllama-macos.sh` rebuild a stage whose stamp is missing or differs from `scripts/llama-cpp.pin`. All three libllama build scripts (macOS, Linux, Windows) also discard their CMake build directory when its `CMakeCache.txt` points at another llama.cpp source tree, so a pin change never stops at cmake's "source does not match the source used to generate cache" error.

### Build stamp

The About page shows `Version 1.4.2 · a1b2c3d · 2026-11-06` (short commit, `+` when the tree was dirty, UTC build date). The values are compile-time `--dart-define=WP_BUILD_COMMIT` / `WP_BUILD_DATE`, printed by `bash scripts/build-stamp.sh` (empty without git). Every release path appends them next to `APP_VERSION`: `scripts/release/{mac-build.sh,linux-build.sh,win-build.ps1}`, `scripts/release-macos-local.sh`, the Fastfile (`build_stamp_flags`, both macOS builds incl. the Mac App Store) and `release.yml`. The macOS flags (MAS marker, release defines file, `APP_VERSION`, stamp) are assembled in one place, `scripts/macos-flutter-build.sh [--mas]`, which both Fastfile lanes (Mac App Store, Developer ID) and the local preview call; a missing release define (`WHISPASTE_MATOMO_URL`, `WHISPASTE_MATOMO_SITE_ID`, from the environment or `~/.config/whispaste/release.env`) stops it. The app logs the same line once at startup (`App build: 1.4.2 · a1b2c3d · 2026-11-06` in `whispaste.log`). The Xcode scheme `Runner (MAS)` has no define path of its own; it reads `macos/Flutter/ephemeral/Flutter-Generated.xcconfig`, which carries the defines of the last `flutter build macos`.

**Local macOS preview (Mac App Store configuration):** `bash scripts/macos-preview.sh` builds with the flags above, runs `xcodebuild` for `Runner (MAS)` into the worktree's own `build/preview-derived` (gitignored; global DerivedData is never used or deleted) and installs exactly that `.app` with `.claude/skills/mas-local-test-install/install.sh` (default target `~/Applications/WhisPaste.app`, the previous copy is replaced without a backup; other `WhisPaste*.app` copies in `~/Applications`, the former `~/Applications/WhisPaste-Backups/` folder and the installed build output are removed so Spotlight shows only the installed copies, #1015). The installer refuses an app whose binary lacks this checkout's HEAD commit or the compiled-in release defines, refuses a dirty stamp (`abc1234+`) for `/Applications`, and after launch checks that the running process is the installed copy and started after the install, then prints version · commit · date (when macOS app data protection denies the shell read access to the sandbox container log, it says so once and relies on the binary check). `--no-install` builds only. The installer signs the preview like the release builds share their secrets (#1380, ADR 0036): `preview_sign_app` in `scripts/release/mac-devid-sign.sh` uses the Developer ID identity (override `WP_MAC_PREVIEW_IDENTITY`), embeds the "de.whispaste.app Developer ID" profile and adds the keychain access group `Q7V3X27S2U.de.whispaste.app` (plus application and team identifier) to the sandboxed MAS entitlements, so preview, Developer ID and Store builds read the same data-protection keychain entries (e.g. `wp_data_key`); signing stops if the group is missing. A build without them (IDE run, plain `flutter run`) shows only the version. A new build path must append `$(bash scripts/build-stamp.sh)`.

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

The pure Swift logic of the macOS runner (paste key per keyboard layout, where the accessibility helper panel goes and which way its arrow points) has XCTest cases in `macos/RunnerTests/`. Run them on the Mac before merging a change to `macos/Runner/`, after one `flutter build macos --debug`:

```bash
cd macos && nice -n 19 xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -configuration Debug -only-testing:RunnerTests -derivedDataPath ../build/macos
```

Delete `build/` afterwards.

### Renderer

The macOS app renders with Skia (`FLTEnableImpeller` is `false` in `macos/Runner/Info.plist`, for every engine and every build configuration). With Flutter 3.47.9, Impeller on Metal stages glyph uploads in a four-frame host buffer ring and does not wait for the GPU before it reuses a slot. If another GPU job delays the upload by more than four frames, the glyph atlas keeps foreign data: text and icons stay broken until restart, while surfaces repair themselves on the next frame. A single queue with 58 ms compute jobs was enough on an Apple M5 (102 of 110 text lines broken, 0 of 110 at 8 ms, 0 of 110 with Skia under the heaviest load). Upstream report with the same trigger: [flutter/flutter#193927](https://github.com/flutter/flutter/issues/193927).

The failure is measured on Metal only; Windows and Linux keep the engine default (Flutter 3.47.9 draws with Impeller on OpenGLES/ANGLE on Windows).

**Windows (checked 2026-11-10, #492):** hp840, Intel Iris Xe, release build of a throwaway Flutter app, Impeller OpenGLES (engine default). Steps 1, 3 and 4 below with 110 lines x 5 repeats (550 lines, fresh sizes and texts per pass, offscreen `toImage`, reference taken in a separate run without load). The load was a WebGL fragment shader in Edge at about 100 % on the 3D engine, so another process rather than a second queue of the same process. Result: 6 of 550 lines differ from the reference under load, and the same 6 count differ between two reference runs without any load (the last lines of the first two passes), so the load causes no difference; no broken atlas, no persistent damage. Note: the app must run in the interactive desktop session (a started-from-service shell fails with `0x887A0022`). Not shown on Windows; no renderer change.

**Linux: not measured.** `tc-m93p` (host key `SHA256:z+plXC7v8iD0xMa47xFrosMic6BW9z0gY0uLUyCFDFQ`, verified) accepts no SSH key of the hp840 (`Permission denied (publickey)`). Open until a key is authorised there; the engine default stays until then.

To lift the setting after a Flutter update, run this check with Impeller enabled (the key set to `true` in a throwaway Flutter macOS app on the new SDK, not in the repo). The test app is not kept in the repo; write it again from these steps:

1. Draw a column of about 110 text lines, each with a new text and a new font size on every pass, so the glyph atlas needs fresh uploads.
2. Start a second Metal command queue in the same process that submits compute jobs of about 60 ms each, back to back (40 to 60 ms is enough on an Apple M5; 8 ms jobs never failed).
3. Pass A: draw the lines while the jobs run. Pass B: stop the jobs, wait until the GPU is idle, redraw the same lines. Pass C: the same two passes with no jobs at all, as reference.
4. Compare the rendered lines of A and B with C pixel by pixel (offscreen `toImage`, no screenshots by hand).

The setting can go when no line of A or B differs from C over at least 5 repeats. With the current SDK 102 of 110 lines differ. Check this before each release that raises Flutter.

### Package lockfiles

Every `packages/*/` package keeps its `pubspec.lock` (and the `analyzer: exclude` that `flutter pub get` writes into `packages/auto_updater_windows/analysis_options.yaml`) committed, so the `flutter pub get` of a test run (`wp-test.sh`) leaves the worktree clean; a dirty tree blocks the gate stamp. After a Flutter SDK bump (`.flutter-version`) run `flutter pub get` in each package and commit the changed lockfiles with the bump. `macos/Flutter/GeneratedPluginRegistrant.swift` is the exception: `flutter pub get` drops its `#if !MAS_BUILD` guard; the `mas-guard` filter (see "No noise" under macOS plugin files) hides that from git once `scripts/install-git-filters.sh` has run, otherwise the tree stays dirty.

### macOS plugin files

`macos/Flutter/GeneratedPluginRegistrant.swift` and `macos/Podfile.lock` are generated, but committed: the Mac build links exactly the plugins they name. They follow from `pubspec.lock`, `macos/Podfile` and the Flutter SDK in `.flutter-version`. Nobody edits them by hand:

```bash
bash scripts/sync-macos-plugins.sh          # macOS: pub get + pod install, both files rewritten
```

- **Commit:** when `pubspec.yaml`, `pubspec.lock`, `.flutter-version`, `macos/Podfile` or `macos/.cocoapods-version` is in a commit, the pre-commit hook runs the sync on the Mac and stages both files into the same commit (only these two). It never blocks the commit. If the sync fails or takes longer than 120 s (offline, no CocoaPods, a stale spec repo, another sync holding the lock), the hook prints a warning and the fix command. Commits without these inputs do not touch pod.
- **Push:** the pre-push hook compares the plugin names in both committed files with the macOS plugins `flutter pub get` resolved (`dart tool/macos_plugins.dart`, under a second). Real drift blocks on the Mac (run `flutter pub get` explicitly if the resolved list predates the last checkout) and only warns elsewhere. A check that cannot tell (no `pub get` yet, uncommitted pubspec changes) never blocks. Version-only changes are not part of this check: the commit hook takes them in with the pubspec change.
- **Fast push, required server gate:** `bash scripts/check.sh prepush [dev]` (also `push`) runs only the actual branch's pre-push protection checks: private-code/export and release guards, branch hygiene, secret scans over the pushed range, docs attestation, logging and workflow pin/timeout guards, and quick generated-file checks/self-healing. It runs no tests, builds, package downloads, upstream network queries or workflow lint, and writes no gate stamp. The target is under 10 seconds for an ordinary feature push; production release guards still apply separately.
- **Before merge:** `.internal forge/workflows/gate.yml` is a quick check on the NAS light lane (`nas-gate-light`, #1403): repo guards, gitleaks over the changed range, `dart format` and shellcheck, without a Flutter SDK. The required status `gate/nas` reports failure if any check fails and blocks merging into `dev`. A push to `dev` whose SHA already carries a genuine `gate/nas=success` (the PR head before the fast-forward merge) reuses that status instead of a second run; test `scripts/ci/gate-reuse.test.py`.
- **After merge:** the existing `.internal forge/workflows/lab.yml` runs `flutter analyze --no-pub --fatal-infos --fatal-warnings` over `lib test integration_test tool generators benchmarks` (only when one of these paths, `packages/`, pubspec or `analysis_options.yaml` changed since the last successful analysis, area `dart` of `scripts/ci/lab-changes.sh`), then unit/contract tests and hook helper tests on `dev`; `.internal forge/workflows/lab-full.yml` runs journeys, website E2E and desktop builds there. Both bundle queued merges without cancelling an active run; the full lane also retains its nightly/manual triggers. Tests/builds have no second pre-push or stamp path.
- **Docs attestation and rebases:** the pre-push hook lets a commit through when `scripts/docs-attest.sh attested` names it, when its tree was attested on this machine, or when its docs fingerprint was (`attested-tree`). `docs-attest.sh attest` records the tree and the fingerprint, a hash over the files under `DOCS_PATHS` in the script (README, SECURITY, CONTRIBUTING, CHANGELOG, `store/`, `website/`, `pubspec.yaml`, `lib/core/app_urls.dart`; the public docs the checks read; the hook runs `docs-attest.sh check` on the working tree in addition, which also scans `lib/` for store URL literals). So a rebase of an attested PR branch (coordinator merge, `fj ready`) passes without a new attest as long as those files are byte-identical to an attested commit; if `dev` has changed those files meanwhile (about every second merge adds a `CHANGELOG.md` entry), the commit still counts when its docs diff is the attested one: `attest` also records a hash of the exact content of `git diff -U0 <merge-base with origin/dev>..<commit> -- DOCS_PATHS` (`docs-attest.sh diff-id`: file names and changed lines byte for byte, without line numbers, so the position of a line within its file is not part of it; for a commit that leaves the docs alone the diff id is the patch-id of its whole diff, so a code-only PR rebased over docs changes of `dev` stays attested, #741), and `attested-tree` accepts a commit whose diff id is on that list. For such a code-only commit the docs are the `dev` state's docs; that state is not attested again by this path. The base is an ancestor of `origin/dev` by construction, so a docs change that sits on no dev state shows up in the diff; without `origin/dev` the check fails closed. If the rebase changes the diff itself (e.g. a conflict in `CHANGELOG.md` resolved to different content), the push stays blocked until `scripts/docs-attest.sh attest` is run again. Logic test: `scripts/docs-attest.test.sh` (part of the existing Lab run on `dev`).
- **No noise:** git clean filters normalize what is not a real change. `mas-guard` restores the `#if !MAS_BUILD` guard around the auto-updater, which every `flutter pub get/analyze/test` drops; a Mac App Store build without it crashes at launch. `podlock` pins the `COCOAPODS:` line to `macos/.cocoapods-version`, so another local CocoaPods version is no change. `scripts/install-git-filters.sh` sets both filters; the hooks and the sync call it.
- `pod install` runs without `--repo-update`. Pods that only `Podfile.lock` pins (Sparkle) keep their version; raise them with `cd macos && pod update <pod>`, then run the sync. To move to a new CocoaPods, change `macos/.cocoapods-version`.

### Worktrees

`scripts/worktree-prepare.sh` waits (exit 3) only for real builds that share the flutter_soloud cache: `xcodebuild` build/archive/test runs, `flutter assemble` and soloud CMake. A pure `xcodebuild test-without-building` run (the long-lived iPhone runner of agent-device, #833) does not block it.

## sherpa-onnx upstream binaries (ADR 0037, #1253)

The pub packages `sherpa_onnx_{macos,linux,windows}` 2.0.1 already ship the
upstream binaries. They are pinned by hash in `scripts/sherpa-upstream.pin`
and checked with `scripts/verify-sherpa-upstream.sh <macos|linux|windows>`
(lockfile version and archive hash, then every file; `--bundle DIR` on
Linux/Windows also checks the staged bundle). Fetch with
`flutter pub get --enforce-lockfile`. On macOS verify before slice selection
and signing. The own build below stays the shipped path until the acceptance
on all three platforms is done; only then it is removed.

Known gap: the pub archives carry no Windows PDBs and Microsoft's PDBs belong
to a different ORT build, so the upstream Windows DLLs are symbolised by export
names only.

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
  `cmake/onnxruntime-*.cmake` pins the same hash on macOS/Linux. Windows deliberately
  verifies its own Microsoft archive pin instead: ORT 1.28.2 includes matching
  DLL/PDB files for Sentry (#191), unlike sherpa's third-party archive.
  `build-sherpa-onnx.ps1` configures the verified `include/` and `lib/` directories.
  It explicitly sets `location_onnxruntime_lib2` to `lib/onnxruntime.lib` because
  sherpa 2.0.1 leaves this import-library variable unset on its Windows CPU
  preinstalled-runtime path. Remove the workaround once upstream fixes that path.
  Microsoft PDBs stay in `.build/sherpa-onnx/windows-ort-pdb`, outside the app;
  only the local release uploads them (see `internal-notes`).
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

### Residual risk: prebuilt clipboard library from upstream (#674)

`super_native_extensions` (used through `super_clipboard`) ships its Rust part as a
signed prebuilt library from the package's GitHub releases; `cargokit_options.yaml`
makes every build use it whenever one exists for the crate hash. Cargokit verifies the ed25519 signature against the public
key in the pub.dev package (`rust/cargokit.yaml`) and discards a library whose signature
fails. A missing library (HTTP 404) or a failed signature check falls back to a source
build; a network error (no connection, DNS, TLS) does not and stops the build.

- The signature proves the library comes from the upstream key, not that it was built
  from the source we read. A compromised upstream key or release pipeline would pass.
- The key ships in the same pub.dev package as the code that checks it, so the check
  guards against tampered GitHub release assets, not against a tampered package.
- We cannot rebuild the prebuilt library bit for bit.
- Accepted by the maintainer (2026-11-05) for faster builds without Rust on every machine.
- Lift it when a release needs source-built native code: delete
  `cargokit_options.yaml` and install Rust on the build machines.

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

Patches to whisper.cpp: `native/whisper_patches/*.patch` are applied to the pinned source by `scripts/apply-whisper-patches.sh` in every `build-libwhisper-*` script (idempotent; the commit check runs first, the patch hash is part of the macOS `WHISPER_PIN` stamp, so an old stage rebuilds). `0001-reuse-language-detect-encode.patch` (#570): with language `auto`, `whisper_full` encodes the first window once for the language detection and again for the decode; the patch lets the decode reuse that encoder output (same mel, offset 0, same `audio_ctx`; any other case encodes as before). When raising the pin, rebase or drop each patch as well, before step 2 (the build fails otherwise); `bash scripts/apply-whisper-patches.test.sh` checks that they apply (the existing Lab run on `dev` runs it with `--fetch`; a native build also fails if a patch no longer applies), the benchmark `benchmarks/tooling/stt_stage_bench/` must show `encodeRuns` 1 for `auto` (encode count, no timing). `0002-fail-load-on-null-weight-buffer.patch` (#1669): when a weight buffer cannot be allocated (video memory held by other programs), upstream skipped the NULL buffer and aborted the process later in `ggml_backend_buffer_*(NULL)` (0xC0000409 on Windows); the patch logs `failed to allocate <buft> buffer for the model weights (out of memory)` and fails the load, so `whisper_init_*` returns NULL and the app moves to the CPU (same for the VAD model). A failed model load also frees the buffers already allocated (`whisper_free` instead of `delete`). `0003-fail-ggml-init-on-out-of-memory.patch` (#1669): on Windows the driver moves video memory that other programs hold into system memory, so the same repro mostly ran out of system memory (commit limit) instead, and `ggml_init` aborted on `GGML_ASSERT(ctx->mem_buffer != NULL)` (`ggml.c:1644`); the patch logs `failed to allocate <n> bytes for the context (out of memory)` and returns NULL, and the two whisper.cpp callers that did not check it (model and VAD tensor context) fail the load. The lab build caches of libwhisper key on `native/whisper_patches/*.patch` too, so a patch change rebuilds there. The CUDA packs build only `libggml-cuda`, which uses the app's patched `ggml-base`, and need no patch.

The CUDA packs (`scripts/build-cuda-pack-*.{sh,ps1}`) read `scripts/whisper-cpp.pin` too, but carry the whisper.cpp version in their pack id and move with their own pack revision: both scripts stop when the pack id does not name the pinned tag.

### Linux/Windows compile check

A macOS build never compiles the Linux and Windows branches of `native/smart_mode` and `native/ffi_guard`, so a break there stays invisible on the Mac. `scripts/native-compile-check.sh [<range>]` looks at the commit range (default `origin/dev...HEAD`); when it touches `native/smart_mode/`, `native/ffi_guard/` or a `scripts/*.pin`, it compiles the shim and `wp_ffi_guard` against the pinned headers on the lab VMs `ubu` and `win` in parallel (`scripts/native-compile-linux.sh`, `scripts/native-compile-windows.ps1`, about a minute, compile only). It runs in the fast lane after every merge into `dev`; `--force` compiles regardless of the paths. `.githooks/pre-push` no longer prints a note: the `lab/full-ubu` and `lab/full-win` jobs of `.internal forge/workflows/lab-full.yml` build the Linux and Windows app after merges to `dev`. Exit 1 means a real compile error. A busy lab, a lock timeout or a broken VM run is reported as unchecked (exit 3) and never counts as red.

The runners are the second trigger, each on its own guest: `windows/runner/` or `windows/CMakeLists.txt` builds the Windows runner on `win` with `flutter build windows --debug` (`scripts/native-compile-windows-runner.ps1`), `linux/runner/` or `linux/CMakeLists.txt` the Linux runner on `ubu` with `flutter build linux --debug` (`scripts/native-compile-linux-runner.sh`), both incremental on the warm checkout. The Linux native tests (`scripts/ci/linux-native-tests.sh`) compile only the header-only helpers, so a runner source error used to surface only in a release build (#77). The `lab/full-ubu` job (`flutter build linux --release`) and the `lab/full-win` job (`flutter build windows --debug`) of `.internal forge/workflows/lab-full.yml` build the runners after merges to `dev` and fail on a compile error; `.githooks/pre-push` no longer runs these builds.

The Windows backlog lives in `wp-pending-win.txt` inside the shared git directory of the main checkout (`.git/`; untracked, common to all worktrees). `WP_PENDING_WIN=<file>` overrides the location.

## Third-party notices

`THIRD_PARTY_NOTICES.md` is generated: `python3 scripts/generate-third-party-notices.py`
(`--check` fails when it is stale; `flutter test test/core/licenses/` runs that check).

## Windows (x64)

Last verified on Windows on **2026-11-09** with **Flutter 3.47.9** (framework revision `c197ca5199`, reported by `flutter --version`), after a successful `flutter build windows --release --no-tree-shake-icons`.

### Toolchain on a fresh machine

| Tool | winget ID | Why |
|---|---|---|
| VS 2022 Build Tools: workload `VCTools` (MSVC, Windows SDK) **plus** component `VC.ATL` | `Microsoft.VisualStudio.2022.BuildTools` | compiler; `flutter_secure_storage_windows` includes `atlstr.h`, which `VCTools` does not bring, not even with `--includeRecommended` |
| CMake | `Kitware.CMake` | native libraries |
| Ninja | `Ninja-build.Ninja` | generator of the native build scripts |
| Vulkan SDK | `KhronosGroup.VulkanSDK` | GPU backend; sets `VULKAN_SDK`, brings `glslc.exe` |
| PowerShell 7 | `Microsoft.PowerShell` | the build scripts run under `pwsh` |
| Git for Windows | `Git.Git` | sources, plus its `bash.exe` for the espeak-ng guard |
| A JDK (tested: Microsoft OpenJDK 21), `JAVA_HOME` set | `Microsoft.OpenJDK.21` | `sentry_flutter` pulls in the `jni` plugin, whose CMake calls `find_package(JNI)`; without a JDK the configure stops with `Could NOT find JNI` |
| Flutter 3.47.9 | – (`git clone`) | see [Common prerequisites](#common-prerequisites) |

```powershell
winget install -e --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL"
winget install -e --id Kitware.CMake
winget install -e --id Ninja-build.Ninja
winget install -e --id KhronosGroup.VulkanSDK
winget install -e --id Microsoft.OpenJDK.21
git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git C:\tools\flutter
```

The Build Tools, the Vulkan SDK and the JDK ask for administrator rights. winget installs CMake and Ninja as portable packages into `%LOCALAPPDATA%\Microsoft\WinGet\Links`, which it adds to the user `PATH`. Put `C:\tools\flutter\bin` on the user `PATH` yourself, and set `JAVA_HOME` to the JDK folder if its installer did not (`[Environment]::SetEnvironmentVariable('JAVA_HOME', '<jdk folder>', 'User')`).

Two more steps:

- **Developer Mode** (`start ms-settings:developers`): Flutter plugins are linked as symlinks. Without it, `flutter pub get` stops with `Building with plugins requires symlink support`.
- **Open a new terminal** after the installs. A shell started before them sees neither the new `PATH` entries nor `VULKAN_SDK` and `JAVA_HOME`.

Rust is not needed. `super_native_extensions` builds its Rust part through Cargokit, which downloads a signed prebuilt library; `cargokit_options.yaml` (`use_precompiled_binaries: true`) keeps it that way even with `rustup` on the machine (#674). Cargokit compiles from source only when no signed prebuilt library exists for the crate or its signature fails (a network error stops the build instead); then keep Rust stable current (`rustup update stable`).

When the VS Installer stops with exit code 8006 (`VSProcessesRunning`), MSBuild nodes from an earlier build are still running: `taskkill /IM MSBuild.exe /F`, or set `MSBUILDDISABLENODEREUSE=1` for your builds.

### Build

The steps below, in this order, from the repo root in `pwsh`. Rough times on an 8-thread laptop for a first build: sherpa-onnx 6 min, the app 9 min, `libwhisper` 5 min, `libllama` 7 min; warm rebuilds take seconds to a minute. The native build scripts activate the VS 2022 build tools themselves (`scripts/windows-msvc-env.ps1`) when `cl.exe` is not on `PATH`, so a normal terminal is enough.

sherpa-onnx comes first: `windows/CMakeLists.txt` takes the staged build when the app is configured, and without it bundles the pub package's libraries, which contain espeak-ng (see [sherpa-onnx without TTS](#sherpa-onnx-without-tts-all-desktop-platforms)):

```powershell
pwsh -File scripts\build-sherpa-onnx.ps1
```

Then the app. The bundle scripts below copy into its output folder, so it has to exist before them:

```powershell
flutter build windows --release --no-tree-shake-icons
```

A later `flutter build windows` keeps what the bundle scripts copied: after a rebuild, all bundled DLLs are still there, byte for byte. Only `flutter clean` or deleting `build\windows` removes them; then run the bundle scripts again.

`libwhisper` (Vulkan + one CPU backend per x86-64 feature level, plus `wp_ffi_guard`). The script uses the same pin and cmake options as the release workflow. It needs the Vulkan SDK (`VULKAN_SDK`, `glslc.exe`):

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

### Git hooks and local checks (Git Bash)

The hooks and [local checks](#local-checks) are bash scripts; on Windows they run in Git Bash. They need a few tools beyond the build toolchain, all without administrator rights:

```powershell
winget install -e --id Python.Python.3.14 --scope user
py -3 -m pip install --user pyyaml
winget install -e --id rhysd.actionlint --scope user
winget install -e --id Gitleaks.Gitleaks --scope user
```

Then, in Git Bash from the repo root:

```bash
bash scripts/install-hooks.sh
```

It sets `core.hooksPath` to the relative `.githooks`, so every worktree runs its own hooks. Keep it relative: with an absolute path to one checkout, every worktree pushes with that checkout's hooks.

- **Python:** `python3` on Windows is often the Microsoft Store stub, which only prints an install hint. The hooks, the git filters and the workflow check find a real Python 3 themselves (`.githooks/python3.sh`: `python3`, then `py -3`, then `python`). Other scripts call `python3` directly: turn off the `python3.exe` alias (Settings > Apps > Advanced app settings > App execution aliases), or put a `python3` file with `exec py -3 "$@"` into a folder on your Git Bash `PATH`. Set `PYTHONUTF8=1` as well, since Python on Windows reads files as cp1252 by default.
- **PyYAML** is required by the workflow check (`scripts/check-workflow-hygiene.sh`); without it the push stops.
- **gitleaks:** without it the local hook warns; the required NAS gate still scans secrets. Workflow pin/timeout protection stays local; actionlint can be run explicitly while editing workflows. The scan uses gitleaks' default rules plus our own (`.gitleaks.toml` with `[extend] useDefault = true`); a reviewed false positive gets a narrow `[[allowlists]]` entry there (path plus `targetRules`, with the reason), never a blanket exemption (the one global exception matches only the fake value `sk-test-<digits>`, never a path).
- **loam (ratchet gate):** the commit hook and the `lab/ubu` job (`.internal forge/workflows/lab.yml`) run `dart pub global activate loam 0.1.16` (pub.dev, network needed) and then `dart pub global run loam gate`, so no PATH entry is needed on any OS. If activation fails and no copy is installed, the hook stops with an environment error, not with a list of findings. Fix the network or the Dart SDK and run the hook again. In a fresh or throw-away worktree without `.dart_tool/package_config.json` (also the one the coordinator rebases in before a merge) both hooks first resolve the packages themselves (`.githooks/resolve-packages.sh`: `flutter pub get --offline`, then `flutter pub get`), because without them the ratchet reports false "new" findings (#537, #542). `macos/Flutter/GeneratedPluginRegistrant.swift` is restored byte for byte afterwards. If resolving fails, the commit hook warns and the push hook blocks (fail closed). Test: `.githooks/resolve-packages.test.sh` (run by the Lab workflow on `dev`).
- **Optional on Windows:** semgrep and osv-scanner (they run in the `lab/ubu` job, no longer in the pre-push) and cppcheck (the pre-commit warns only when a commit touches `windows/runner/`). CI runs all three.

### Starting a release build next to an installed WhisPaste

A release build from source is not a [local build](#local-builds-keep-their-own-data): it uses the same data folder `%APPDATA%\WhisPaste` and the same single-instance lock as the installed app. While the installed app runs, starting the new `whispaste.exe` only hands over to it (`P ATTACH` on stdout) and exits, so you test the old version without noticing. The version number may well be the same as the installed one; tell the two apart by the path (`Get-Process whispaste | Select-Object Id, Path`).

- Quit the installed app first. It keeps running in the tray on a plain close request, so `taskkill /IM whispaste.exe /F`.
- The first start of the new build migrates the real settings, history and models in `%APPDATA%\WhisPaste`, and the installed version reads them afterwards. On a machine you work on, back that folder up first, use a separate Windows user, or test a `--debug`/`--profile` build, which keeps its own data.

## Linux (x86_64)

The build copies SoLoud's bundled Vorbis libraries into the build tree and uses
`patchelf` to normalize their SONAMEs and the Vorbisfile dependency to
`libvorbis.so.0` / `libvorbisfile.so.3`. The plugin links these copies, which are
bundled with an `$ORIGIN` RUNPATH. This lets the system audio stack reuse the
same libraries instead of loading a second pair under the standard ABI names;
the shared pub cache is never changed. `scripts/check-linux-bundled-codecs.sh`
rejects full-version Vorbis SONAMEs and dependencies in release bundles.

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
  xvfb pulseaudio-utils
```

`pulseaudio-utils` is not needed for `flutter build`: the AppImage step copies its
`parecord` and `pactl` into the AppImage (#1608, `packaging/appimage/README.md`).

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

`bash scripts/ci/packaging-validate.sh [check...]` validates the manifests under `packaging/` (Scoop, Homebrew, Flatpak, AppImage/.deb, Snap, GNOME Shell extension) in a few seconds. It is the one definition: the `packaging-validate` workflow runs it, and the `lab/ubu` job of `.internal forge/workflows/lab.yml` runs it on the lab's Ubuntu guest after merges to `dev` (the pre-push hook no longer does). On the Mac, `scoop homebrew flatpak snap` run directly; `appimage-deb` and `gnome-extension` build a `.deb` with Linux `install(1)` and need the guest. `--install-deps` installs missing validators with apt. winget validation needs Windows and stays in the workflow.

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

`bash scripts/check.sh prepush [dev]` and `push [dev]` run the protection-only hook without pushing. `commit` explicitly runs repo guards, format and analysis. The legacy `tests`, `full` and `pending-win` helpers are diagnostic commands, never called by a hook or a CI workflow; use the existing Lab workflows for automated suites and `labctl test <guest> -- <command>` only to reproduce a specific failure.

**Where labctl is looked up (#460).** `scripts/check.sh`, `scripts/native-compile-check.sh`, `scripts/release.sh` and the stage wrappers `scripts/release/linux-stage.sh` and `scripts/release/win-stage.sh` find `labctl` through `scripts/labctl-path.sh`: `$LABCTL` first (an explicit override), then the shared `~/.claude/bin/labctl` (the same path on every worker device, Mac and Windows), then `labctl` on `PATH`, and last the lab's own checkout `~/Developer/repos/<org>/testlab/bin/labctl` (the release Mac had it only there on the first real release run, #1722). If none exists, `native-compile-check.sh` exits 2 and names the places it looked (the check stays closed), `check.sh` tries the Windows run as before; the push hook never invokes the lab. Test: `scripts/check.test.sh` §13.

**Lab checks run in CI, not in the pre-push hook (#1024).** Fast lane `.internal forge/workflows/lab.yml` (`lab/ubu`, `lab/win`): `flutter analyze` (moved from `gate/nas`, #1403) plus unit and contract tests under `tool/test_guard.dart`, which enforces the hard limits (a passing test over 10 s is red, 20 s without a reporter event ends the run and names the running test, a run over 3 min is red) and lists the slowest tests; the Windows job runs only on Windows-relevant paths (`LAB_ONLY`), otherwise it is green as "not needed". Full lane `.internal forge/workflows/lab-full.yml` (`lab/full-ubu`, `lab/full-win`): journeys (also under `tool/test_guard.dart`, same hard limits, a hung test aborts the run red and names the running test; 5 min step timeout as backstop, 60 min job limit as outer bound for the whole run, #1434), website E2E and release builds, after merges to `dev`, nightly and by manual dispatch; a red run on `dev` opens an issue. Manual lab sessions use `labctl` and write only under `/tmp`.


## Video import helper

Desktop builds automatically stage an audio-only FFmpeg helper in
`.build/video-decoder/<linux|macos|windows>`. It extracts audio from imported
videos (ADR 0037) and encodes the Opus/WebM upload copy of cloud transcription
(ADR 0040). The first build downloads SHA-256-verified upstream source archives
of FFmpeg and libopus (statically linked, BSD-3-Clause); subsequent builds
reuse the helper. No system FFmpeg installation is required by users. The
executable, LGPL and libopus texts, both complete matching source archives and
the build recipe are included in every app bundle.
`scripts/build-video-decoder.py` is the source/version/build-option reference;
update its pins and the FFmpeg/libopus entries in the third-party notices when
updating the helper. FFmpeg's configure finds libopus only via pkg-config; the
script writes a small shim for exactly that, so no pkg-config is needed.

Build prerequisites: Python 3.12 or later, a C compiler and GNU make. macOS
builds run on Apple Silicon with Xcode command-line tools. Windows builds use
Visual Studio's x64 tools plus MSYS2 bash/make at `C:/msys64/usr/bin` (install
`make` in MSYS2 with `pacman -S --needed make`); CMake supplies `vcvars64.bat`
and builds libopus with the static C runtime (`/MT`, FFmpeg's MSVC default).
The helper is a native Windows executable and does not ship an MSYS runtime.
CMake and the Xcode embed phase fail rather than create a package without it.

For an isolated Linux decoder build and fixture check:

```sh
python3 scripts/build-video-decoder.py --platform linux
python3 test/scripts/video_audio_decode_test.py .build/video-decoder/linux/ffmpeg
```

The same fixture check accepts the macOS helper or Windows `ffmpeg.exe` path.
The test fixture README records how the tiny video clips were produced.


## sherpa CoreML / DirectML (#1793)

`bash scripts/build-sherpa-onnx.sh macos` keeps the pinned dynamic ORT 1.28.2
universal library. It already contains CoreML; `otool -L` must be run on
**libonnxruntime.dylib**, not only on the sherpa C API. The build now checks that
framework dependency and records `providers: cpu coreml` in `BUILD_INFO`.

`powershell -File scripts/build-sherpa-onnx.ps1` builds ORT **1.28.2** with
DirectML locally first (`scripts/build-onnxruntime-directml.ps1`). Requirements:
x64 Visual Studio C++ tools, CMake, Ninja, Python 3.10+, Git and Internet for the
first dependency fetch. No paid build service, CUDA toolkit or NVIDIA-only
runtime is required. ORT's source commit and its Git tree are in
`onnxruntime-directml.pin`; its upstream dependency hashes remain active.
Source order: Microsoft's repository first, then Git mirrors from
`WP_ORT_SOURCE_MIRRORS` (`;`-separated URLs or paths, process or Windows user environment, cloned with `--no-local`,
checked against the pinned commit and tree), then Software Heritage
(`scripts/fetch-ort-source-swh.py`: recomputes the Git tree hash from the
archive bytes, refuses any other tree, checks out the submodules at the commits
the tree names). On 2026-11-24 `github.com/microsoft/onnxruntime` answered 404;
that is why the fallback exists. The CPU-only path (`-CpuOnly`) likewise tries
Microsoft's release archive first, then byte-identical copies under
`WP_ORT_ARCHIVE_MIRRORS` base URLs, all against the same SHA-256 pin. Configure and compile are split
so the restored DirectML 1.15.4 NuGet archive is checked against our SHA-256 and
re-extracted before compilation. The resulting DLL, headers and matching PDBs
are cached with a recipe hash and individual file hashes. The sherpa stage
contains `DirectML.dll` in addition to the C API and ORT. The app CMake bundles
all three; PDBs remain outside the app. First builds are substantially longer
than the previous prebuilt CPU-ORT path; subsequent verified-cache builds reuse
it. `-Jobs` on the ORT script limits compiler parallelism (default two).

For an independent build directory, the ORT script accepts `-SourceDir` and
`-BuildDir`; the same source commit and dependency checks apply. These options
were used under `C:\tmp\wp1793` in the lab. `-CpuOnly` on the sherpa script
retains the former Microsoft CPU-ORT recipe for comparisons and stages into
`windows-cpu`, with separate PDB directories; release consumers use `windows`.

The small, checked-in `sherpa-provider.patch` preserves normal CPU execution of
unsupported operators, but turns a failed EP registration into a recognizer
creation error. The app can then retry CPU and report its actual selected
backend. DirectML uses ORT's high-performance GPU selection rather than assuming
that display adapter 0 supports DirectX 12 (important on hybrid/virtual displays).
The patch also makes sherpa consume the verified DirectML dependency
instead of downloading its older default. Its hash is recorded in `BUILD_INFO`;
the stage check rejects stages predating the patch. Linux still builds CPU only.

Selection is gated per exact model (`parakeetSherpaFasterProviders`), not by
provider availability alone. The ggml Parakeet route remains preferred. The
same GPU setting, a separate persistent crash marker and CPU retry govern the
sherpa route. Benchmarks, observed limitations, and byte sizes are recorded in
`benchmarks/sherpa_gpu/README.md` and `benchmarks/results/sherpa-gpu-1793/`.
