# WhisPaste AI Inference

## STT (Speech-to-Text)
### Local (Desktop)
- whisper.cpp `whisper-server` subprocess
- Binaries: CUDA (NVIDIA), Vulkan (AMD/Intel), OpenBLAS (CPU)
- Download from `ggml-org/whisper.cpp` GitHub releases
- Vulkan binary: custom-built via `build-whisper-server.yml` workflow
- Models: Tiny → Large v3 Turbo (31MB → 547MB)
- All models verified via SHA256 before use

### Cloud (All Platforms)
- OpenAI Whisper API
- Groq Whisper API
- Deepgram Nova API
- Interface: `SttProvider.transcribe(audio, language, options)`

## LLM (Post-Processing)
- Settings UI + provider scaffolding exist
- LLM execution NOT wired yet — logs "skipping (not yet implemented)"
- Planned: llama.cpp `llama-server` subprocess
- 3 presets ONLY: cleanup, concise, translate

## GPU Detection Flow
```
Detect() → nvidia-smi → NVIDIA? → CUDA backend
                       → no: platform-specific (WMI/IOKit/sysfs)
                             → AMD/Intel? → Vulkan backend
                             → no: CPU fallback
```

## Binary Selection
| GPU | STT Binary | LLM Binary |
|-----|-----------|-----------|
| NVIDIA | `cublas-12` | `cuda-12` |
| AMD/Intel | `vulkan` | `vulkan` |
| CPU | `openblas` | `cpu` |

## VRAM Safety
- `TierSafety` enum: usable, slowWithoutGpu, vramRisky, vramCritical
- All tiers ALWAYS selectable — warnings only, NEVER disabled
- CUDA OOM detected from stderr at runtime → pipeline recovery
- User decides next action explicitly (no magic auto-switch)

## Service Architecture
- `SttService`: subprocess lifecycle, health polling, cold/warm start
- `ModelDownloadService`: binary + model download, SHA256, progress
- `HardwareInfoService`: GPU detection, VRAM measurement, binary recommendation
