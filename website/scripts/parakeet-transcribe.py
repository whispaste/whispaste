#!/usr/bin/env python3
"""Transcribes every WAV in the LibriSpeech test set with Parakeet
(sherpa-onnx), using the exact same model config as the app's own
`ParakeetEngineNotifier` (lib/services/stt_parakeet/parakeet_engine_notifier.dart):
provider=cpu, model_type=nemo_transducer, greedy_search decoding.

Loads the ~650MB encoder once, then transcribes every utterance in one
process (loading it per-file would dominate the timing). Prints one JSON
line per utterance to stdout so `benchmark-engines-parakeet.mjs` can
aggregate RTF/WER the same way `benchmark-engines-testset.mjs` does for
whisper.cpp.

Requires: pip install sherpa-onnx numpy (not vendored — see the runbook in
`benchmark-engines-parakeet.mjs`'s docstring).

Usage:
    python3 parakeet-transcribe.py --model-dir /path/to/parakeet-tdt-0.6b-v3 \
        --testset-dir librispeech-sample --num-threads 8
"""

import argparse
import glob
import json
import os
import time
import wave

import numpy as np
import sherpa_onnx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--testset-dir", required=True)
    parser.add_argument("--num-threads", type=int, default=8)
    args = parser.parse_args()

    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=os.path.join(args.model_dir, "encoder.int8.onnx"),
        decoder=os.path.join(args.model_dir, "decoder.int8.onnx"),
        joiner=os.path.join(args.model_dir, "joiner.int8.onnx"),
        tokens=os.path.join(args.model_dir, "tokens.txt"),
        num_threads=args.num_threads,
        provider="cpu",
        model_type="nemo_transducer",
    )

    wav_paths = sorted(glob.glob(os.path.join(args.testset_dir, "*.wav")))
    for path in wav_paths:
        utterance_id = os.path.splitext(os.path.basename(path))[0]
        with wave.open(path, "rb") as wf:
            sample_rate = wf.getframerate()
            num_frames = wf.getnframes()
            audio = (
                np.frombuffer(wf.readframes(num_frames), dtype=np.int16).astype(
                    np.float32
                )
                / 32768.0
            )
            audio_duration_ms = num_frames / sample_rate * 1000

        t0 = time.perf_counter()
        stream = recognizer.create_stream()
        stream.accept_waveform(sample_rate, audio)
        recognizer.decode_stream(stream)
        processing_ms = (time.perf_counter() - t0) * 1000

        print(
            json.dumps(
                {
                    "id": utterance_id,
                    "hypothesis": stream.result.text,
                    "audioDurationMs": audio_duration_ms,
                    "processingMs": processing_ms,
                }
            ),
            flush=True,
        )


if __name__ == "__main__":
    main()
