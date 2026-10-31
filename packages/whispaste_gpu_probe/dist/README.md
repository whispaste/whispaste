# WhisPaste-GPU-Probe — Runtime Bundling Layout

This file documents the directory layout required for a distributable
WhisPaste-GPU-Probe bundle. The `dist/` directory is the staging area
produced by `tool/build_exe.sh`.

## Build

```
cd packages/whispaste_gpu_probe
bash tool/build_exe.sh
```

> **Cross-compile limitation:** `dart compile exe` produces a native AOT
> binary for the **host platform only**. To build `WhisPaste-GPU-Probe.exe`
> (Windows), the script must run on a Windows host or a `windows-latest`
> GitHub Actions runner. There is no cross-compilation path.

## Expected dist/ layout after build + manual engine staging

```
dist/
├── README.md                          ← this file
├── WhisPaste-GPU-Probe.exe            ← AOT binary (built by build_exe.sh)
│
├── assets/                            ← reference WAV clips (staged by build_exe.sh)
│   ├── reference_short.wav            ← ~5–8 s mono 16 kHz PCM (PLACEHOLDER)
│   ├── reference_short.txt            ← expected transcript (PLACEHOLDER)
│   ├── reference_long.wav             ← ~60–90 s mono 16 kHz PCM (PLACEHOLDER)
│   └── reference_long.txt             ← expected transcript (PLACEHOLDER)
│
└── engines/                           ← engine binaries (populated MANUALLY or by CI)
    ├── whisper-cpp-cpu/
    │   └── whisper-cpp.exe            ← whisper.cpp CPU-only build
    ├── whisper-cpp-cuda/
    │   ├── whisper-cpp.exe            ← whisper.cpp CUDA build
    │   └── *.dll                      ← CUDA runtime DLLs
    ├── whisper-cpp-vulkan/
    │   ├── whisper-cpp.exe            ← whisper.cpp Vulkan build
    │   └── *.dll                      ← Vulkan runtime DLLs
    └── whisper-cpp-directml/
        ├── whisper-cpp.exe            ← whisper.cpp DirectML build
        └── *.dll                      ← DirectML runtime DLLs
```

## Runtime asset resolution

The probe executable resolves all paths **relative to `--output-dir`** (the
report destination) and locates engine binaries by looking in a sibling
`engines/<candidate-id>/` directory next to the executable itself:

```
<exe-dir>/engines/<candidateId>/<binary>
```

Example: if the exe is at `C:\Tools\WhisPaste-GPU-Probe.exe`, the CUDA
whisper.cpp binary is expected at:
`C:\Tools\engines\whisper-cpp-cuda\whisper-cpp.exe`

Reference WAV clips are resolved from:
`<exe-dir>/assets/reference_short.wav`
`<exe-dir>/assets/reference_long.wav`

## Models

Whisper model files (`.bin`) are **not bundled** — they are large (75 MB –
1.5 GB per model) and downloaded on demand by Slice 06. The probe looks for
models in the user-configured model directory passed via `--model-dir` (TBD
in Slice 06). During the tracer-bullet phase, the fake candidate ignores the
model path.

## No installation required

The exe is self-contained (no separate Dart runtime). It requires no
installation, no admin rights, and no PATH changes. Double-click or run
from a terminal directly.

## Smoke test (CI)

```
WhisPaste-GPU-Probe.exe --output-dir %TEMP%\gpu-probe-smoke --no-deliver
```

`--no-deliver` suppresses the file-manager reveal and mail steps so the
test exits cleanly on headless runners. The exit code is 0 on success; the
report files are written to `%TEMP%\gpu-probe-smoke\`.
