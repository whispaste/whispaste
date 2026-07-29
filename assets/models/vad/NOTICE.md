# ggml-silero-v5.1.2.bin — vendored VAD model

Silero VAD (v5.1.2), converted to ggml format for `whisper.cpp`'s built-in
Voice Activity Detection support (`whisper_vad_*` API, whisper.cpp v1.8.4+).

- **Source:** https://huggingface.co/ggml-org/whisper-vad
- **License:** MIT (redistribution permitted)
- **SHA-256:** `29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf`
- **Size:** 885,098 bytes

Used by [`whisper_ffi_engine.dart`](../../../lib/services/stt/whisper/whisper_ffi_engine.dart)
to trim long silence/noise tails before decoding — the mitigation for
Whisper's documented trailing-silence hallucination class (e.g. fabricated
"Vielen Dank." closings). Toggle: `SttSettings.vadEnabled`.

Bundled at build time next to the platform's `libwhisper` shared library
(same mechanism, see `macos/embed_libwhisper.sh`,
`scripts/bundle-libwhisper-windows.ps1`,
`scripts/build-libwhisper-linux.sh`), not downloaded at runtime — it is
tiny (<1 MB) and does not vary by platform, unlike the multi-gigabyte STT
models users pick and download separately.
