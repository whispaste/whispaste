# onnx-directml runner

The runner binary the Dart `onnx-directml` engine spawns. It runs a Whisper
encoder/decoder ONNX pair through **ONNX Runtime's DirectML execution provider**
so the bench can measure DirectML Whisper performance on the user's GPU.

`whisper_onnx_directml.py` is the source; the bench expects a built
`whisper-onnx-directml.exe` in `onnx-directml/` next to the probe exe.

## CLI contract (fixed by `OnnxDirectMlCandidate`)

```
whisper-onnx-directml --model <dir> --language <lang> --wav <wav>
```

* `--model` is a **directory** holding `encoder_model_int8.onnx`,
  `decoder_model_int8.onnx` and `tokenizer.json` — exactly the bundle the
  `onnx-whisper` model family downloads into `models/<id>/` (see
  `model_store.dart`, `onnxc(...)`).
* On success it prints one `transcript: <text>` line to stdout. `[whisper-onnx]`
  lines are progress/heartbeat only and are ignored by the Dart parser — they
  exist to feed the ProbeRunner heartbeat through the slow first DirectML
  inference (shader compile), emitted from a daemon thread so a blocking
  `InferenceSession.run` can't starve it.
* Non-zero exit → classified as a crash by the Dart side (e.g. the DirectML
  device-hung HRESULT `0x887A0006` on hardware where DirectML is in maintenance
  mode).

## Model source

`onnx-community/whisper-<size>` (public). Microsoft's `whisper-*-directml`
repos — the original catalogue source — went private (HTTP 401), so both the
catalogue (`model_store.dart`) and this runner use the onnx-community export.
The runner needs no torch/transformers: the log-mel front-end is implemented in
numpy to match openai-whisper's `log_mel_spectrogram` (Slaney mel filterbank,
n_fft=400, hop=160, 80 bins), and decoding is a plain greedy loop over the
non-merged decoder with `tokenizers` for detokenisation.

## Build (Windows, Python 3.12)

```powershell
py -m pip install onnxruntime-directml numpy tokenizers pyinstaller
py -m PyInstaller --onedir --name whisper-onnx-directml --noconfirm `
   whisper_onnx_directml.py
# Ship the resulting dist/whisper-onnx-directml/ as onnx-directml/ next to the
# probe exe (exe + _internal/ ~ 120 MB; onnxruntime DirectML DLLs bundled).
```

Runtime deps (`onnxruntime-directml`, `numpy`, `tokenizers`) are bundled by
PyInstaller — the shipped folder is self-contained, no system Python required.
