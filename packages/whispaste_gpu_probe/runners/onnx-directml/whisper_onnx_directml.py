#!/usr/bin/env python3
"""WhisPaste GPU-Probe — ONNX Runtime + DirectML Whisper runner.

This is the runner binary the Dart ``onnx-directml`` engine spawns. It runs a
Whisper encoder/decoder ONNX pair (the public ``onnx-community/whisper-*``
export) through ONNX Runtime's **DirectML execution provider** so the bench can
measure DirectML Whisper performance on the user's GPU.

CLI contract (fixed by ``OnnxDirectMlCandidate`` in the Dart side):

    whisper-onnx-directml --model <dir> --language <lang> --wav <wav>

* ``--model`` is a directory holding ``encoder_model*.onnx``,
  ``decoder_model*.onnx`` (non-merged, no KV-cache branch) and
  ``tokenizer.json``.
* On success the runner prints exactly one ``transcript: <text>`` line to
  stdout. Progress/info lines are prefixed ``[whisper-onnx]`` and ignored by the
  Dart parser — they exist to feed the ProbeRunner heartbeat during the slow
  DirectML model load / first-inference shader compile.
* A non-zero exit code is classified as a crash by the Dart side; the DirectML
  device-hung HRESULT 0x887A0006 surfaces that way on hardware where DirectML
  is in maintenance mode.

Dependencies (no torch): ``onnxruntime-directml``, ``numpy``, ``tokenizers``.
The log-mel front-end is implemented in numpy to match openai-whisper's
``log_mel_spectrogram`` (Slaney mel filterbank, n_fft=400, hop=160, 80 bins).
"""

import argparse
import os
import sys
import threading
import time
import wave

import numpy as np

SAMPLE_RATE = 16000
N_FFT = 400
HOP = 160
N_MELS = 80
CHUNK_SAMPLES = SAMPLE_RATE * 30  # Whisper works on 30s windows.
MAX_NEW_TOKENS = 220


def info(msg):
    """Heartbeat/progress line — ignored by the Dart parser, keeps it alive."""
    print(f"[whisper-onnx] {msg}", flush=True)


def start_heartbeat():
    """Emits a progress line every few seconds on a daemon thread.

    The first DirectML inference blocks for ~20-30s while ONNX Runtime compiles
    shaders for the GPU. Without periodic output the Dart ProbeRunner would hit
    its heartbeat timeout and (wrongly) classify the run as ``hung``. Returns the
    stop event the caller sets when the work is done.
    """
    done = threading.Event()

    def beat():
        while not done.wait(8):
            print("[whisper-onnx] working (DirectML)...", flush=True)

    threading.Thread(target=beat, daemon=True).start()
    return done


# ---------------------------------------------------------------------------
# Audio + log-mel front-end (numpy, matches openai-whisper)
# ---------------------------------------------------------------------------

def read_wav_mono16k(path):
    """Reads a PCM WAV as float32 mono at 16 kHz (linear-resamples if needed)."""
    with wave.open(path, "rb") as w:
        n_ch = w.getnchannels()
        sw = w.getsampwidth()
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
    if sw != 2:
        raise ValueError(f"only 16-bit PCM WAV supported (got sampwidth={sw})")
    audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if n_ch > 1:
        audio = audio.reshape(-1, n_ch).mean(axis=1)
    if sr != SAMPLE_RATE:
        # Simple linear resample — adequate for speech ASR fronts.
        idx = np.linspace(0, len(audio) - 1, int(round(len(audio) * SAMPLE_RATE / sr)))
        audio = np.interp(idx, np.arange(len(audio)), audio).astype(np.float32)
    return audio


def hz_to_mel_slaney(freq):
    freq = np.asarray(freq, dtype=np.float64)
    f_sp = 200.0 / 3
    min_log_hz = 1000.0
    min_log_mel = min_log_hz / f_sp
    logstep = np.log(6.4) / 27.0
    linear = freq / f_sp
    log = min_log_mel + np.log(np.maximum(freq, 1e-9) / min_log_hz) / logstep
    return np.where(freq >= min_log_hz, log, linear)


def mel_to_hz_slaney(mels):
    mels = np.asarray(mels, dtype=np.float64)
    f_sp = 200.0 / 3
    min_log_hz = 1000.0
    min_log_mel = min_log_hz / f_sp
    logstep = np.log(6.4) / 27.0
    linear = f_sp * mels
    log = min_log_hz * np.exp(logstep * (mels - min_log_mel))
    return np.where(mels >= min_log_mel, log, linear)


def mel_filterbank():
    """librosa.filters.mel(sr=16000, n_fft=400, n_mels=80, norm='slaney')."""
    n_freqs = N_FFT // 2 + 1
    fft_freqs = np.linspace(0, SAMPLE_RATE / 2, n_freqs)
    mel_min = hz_to_mel_slaney(0.0)
    mel_max = hz_to_mel_slaney(SAMPLE_RATE / 2)
    mel_points = np.linspace(mel_min, mel_max, N_MELS + 2)
    hz_points = mel_to_hz_slaney(mel_points)
    fdiff = np.diff(hz_points)
    ramps = hz_points[:, None] - fft_freqs[None, :]
    weights = np.zeros((N_MELS, n_freqs), dtype=np.float64)
    for i in range(N_MELS):
        lower = -ramps[i] / fdiff[i]
        upper = ramps[i + 2] / fdiff[i + 1]
        weights[i] = np.maximum(0.0, np.minimum(lower, upper))
    # Slaney normalisation.
    enorm = 2.0 / (hz_points[2:N_MELS + 2] - hz_points[:N_MELS])
    weights *= enorm[:, None]
    return weights.astype(np.float32)


def log_mel_spectrogram(audio, filters):
    audio = np.pad(audio, (N_FFT // 2, N_FFT // 2), mode="reflect")
    window = np.hanning(N_FFT + 1)[:-1].astype(np.float32)  # periodic Hann
    n_frames = 1 + (len(audio) - N_FFT) // HOP
    stft = np.empty((N_FFT // 2 + 1, n_frames), dtype=np.complex64)
    for i in range(n_frames):
        frame = audio[i * HOP: i * HOP + N_FFT] * window
        stft[:, i] = np.fft.rfft(frame)
    magnitudes = (np.abs(stft[:, :-1]) ** 2)  # drop last frame, like torch.stft
    mel_spec = filters @ magnitudes
    log_spec = np.log10(np.maximum(mel_spec, 1e-10))
    log_spec = np.maximum(log_spec, log_spec.max() - 8.0)
    log_spec = (log_spec + 4.0) / 4.0
    return log_spec.astype(np.float32)


def make_input_features(audio, filters):
    """Pads/trims to a 30s window → mel [1, 80, 3000]."""
    if len(audio) < CHUNK_SAMPLES:
        audio = np.pad(audio, (0, CHUNK_SAMPLES - len(audio)))
    else:
        audio = audio[:CHUNK_SAMPLES]
    mel = log_mel_spectrogram(audio, filters)  # [80, 3000]
    return mel[None, :, :]


# ---------------------------------------------------------------------------
# ONNX session helpers
# ---------------------------------------------------------------------------

def pick_file(model_dir, prefix):
    """Prefers an int8 export, then plain, for encoder/decoder_model*.onnx."""
    candidates = [
        f"{prefix}_int8.onnx",
        f"{prefix}.onnx",
        f"{prefix}_quantized.onnx",
        f"{prefix}_uint8.onnx",
    ]
    for name in candidates:
        path = os.path.join(model_dir, name)
        if os.path.exists(path):
            return path
    raise FileNotFoundError(f"no {prefix}*.onnx in {model_dir}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="model directory")
    ap.add_argument("--language", default="de")
    ap.add_argument("--wav", required=True)
    args = ap.parse_args()

    t0 = time.time()
    info("starting ONNX Runtime + DirectML")
    heartbeat = start_heartbeat()

    import onnxruntime as ort
    from tokenizers import Tokenizer

    providers = ["DmlExecutionProvider", "CPUExecutionProvider"]
    so = ort.SessionOptions()
    so.log_severity_level = 3

    enc_path = pick_file(args.model, "encoder_model")
    dec_path = pick_file(args.model, "decoder_model")
    info(f"loading encoder {os.path.basename(enc_path)}")
    enc = ort.InferenceSession(enc_path, sess_options=so, providers=providers)
    info(f"encoder provider: {enc.get_providers()[0]}")
    info(f"loading decoder {os.path.basename(dec_path)}")
    dec = ort.InferenceSession(dec_path, sess_options=so, providers=providers)

    tok = Tokenizer.from_file(os.path.join(args.model, "tokenizer.json"))

    def tid(token):
        i = tok.token_to_id(token)
        if i is None:
            raise ValueError(f"token {token} not in tokenizer")
        return i

    sot = tid("<|startoftranscript|>")
    lang = tid(f"<|{args.language}|>")
    transcribe = tid("<|transcribe|>")
    no_ts = tid("<|notimestamps|>")
    eot = tid("<|endoftext|>")

    info("front-end: log-mel spectrogram")
    audio = read_wav_mono16k(args.wav)
    feats = make_input_features(audio, mel_filterbank())

    enc_in = enc.get_inputs()[0].name
    enc_out = enc.get_outputs()[0].name
    info("running encoder on DirectML")
    hidden = enc.run([enc_out], {enc_in: feats})[0]

    dec_in_names = {i.name for i in dec.get_inputs()}
    dec_out = dec.get_outputs()[0].name
    ids = [sot, lang, transcribe, no_ts]
    info("running decoder (greedy) on DirectML")
    for _ in range(MAX_NEW_TOKENS):
        feed = {
            "input_ids": np.array([ids], dtype=np.int64),
            "encoder_hidden_states": hidden,
        }
        # Some exports expect an explicit encoder attention mask.
        if "encoder_attention_mask" in dec_in_names:
            feed["encoder_attention_mask"] = np.ones(
                (1, hidden.shape[1]), dtype=np.int64
            )
        logits = dec.run([dec_out], feed)[0]
        nxt = int(np.argmax(logits[0, -1]))
        if nxt == eot:
            break
        ids.append(nxt)

    heartbeat.set()
    gen = ids[4:]  # strip the forced prompt
    text = tok.decode(gen, skip_special_tokens=True).strip()
    info(f"done in {time.time() - t0:.1f}s, {len(gen)} tokens")
    print(f"transcript: {text}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 — surface any failure as a crash exit.
        print(f"[whisper-onnx] ERROR: {e}", file=sys.stderr, flush=True)
        sys.exit(1)
