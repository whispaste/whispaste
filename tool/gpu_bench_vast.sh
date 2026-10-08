#!/usr/bin/env bash
# gpu_bench_vast.sh — CUDA vs Vulkan vs CPU whisper benchmark on a rented
# NVIDIA box (handy-catchup ticket 13). Runs the real app headless
# (`whispaste --transcribe-file`, lib/services/headless/) with the optional
# ggml CUDA backend from .github/workflows/build-cuda-backend.yml.
#
# Target: a fresh Vast.ai (or RunPod) Ubuntu 24.04 container as root, e.g.
# image nvidia/cuda:12.8.1-base-ubuntu24.04 with NVIDIA_DRIVER_CAPABILITIES=all
# (the Vulkan run needs the driver's graphics/ICD files inside the container;
# without them it is reported as skipped). Driver >= 570 (CUDA 12.8). Ubuntu
# 24.04 because the bundle and the CUDA module are built on ubuntu-24.04
# runners (glibc 2.39).
#
# Inputs (local path or tokenless URL — GitHub artifacts need auth, so
# download them locally with `gh run download` and scp them up):
#   <bundle.tar.gz>     Linux release bundle: the `headless-benchmark-linux-bundle`
#                       artifact of headless-benchmark.yml (workflow_dispatch),
#                       must contain lib/libwhisper.so
#   <ggml-cuda.tar.gz>  `ggml-cuda-linux-x64` artifact of build-cuda-backend.yml
#
# Usage: bash gpu_bench_vast.sh <bundle.tar.gz|url> <ggml-cuda.tar.gz|url> [out-dir]
# Env:   BENCH_REPEAT (default 5), BENCH_MODELS (default "whisper-medium
#        whisper-large-v3-turbo"), BENCH_CLIPS (seconds, default "10 30")
# Output: <out-dir>/{system.json,<mode>-<model>-<clip>s.json,results.json,results.md}
set -euo pipefail

BUNDLE_SRC="${1:?usage: gpu_bench_vast.sh <bundle.tar.gz|url> <ggml-cuda.tar.gz|url> [out-dir]}"
CUDA_SRC="${2:?usage: gpu_bench_vast.sh <bundle.tar.gz|url> <ggml-cuda.tar.gz|url> [out-dir]}"
OUT="$(mkdir -p "${3:-gpu-bench-results}" && cd "${3:-gpu-bench-results}" && pwd)"
REPEAT="${BENCH_REPEAT:-5}"
MODELS="${BENCH_MODELS:-whisper-medium whisper-large-v3-turbo}"
CLIPS="${BENCH_CLIPS:-10 30}"
WORK="${BENCH_WORK:-/opt/wp-bench}"
SAMPLE_BASE="https://raw.githubusercontent.com/whispaste/whispaste/dev/website/scripts/librispeech-sample"

echo "=== gpu_bench_vast: deps ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Runtime deps of the Linux bundle (packaging/deb/control.template) plus
# Xvfb/dbus (the GTK runner opens its window before Dart's main), lspci for
# the app's GPU detection, and the Vulkan loader for the Vulkan run.
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl python3 xvfb xauth dbus pciutils \
  libgtk-3-0 libsecret-1-0 libnotify4 libayatana-appindicator3-1 libasound2t64 \
  libcurl4 libkeybinder-3.0-0 liblzma5 zlib1g libvulkan1 vulkan-tools >/dev/null

fetch() { # <path-or-url> <dest>
  if [[ "$1" =~ ^https?:// ]]; then
    curl -fsSL --retry 3 --retry-delay 5 -o "$2.part" "$1" && mv "$2.part" "$2"
  else
    cp "$1" "$2"
  fi
}

mkdir -p "$WORK"/{bundle,cuda,models/stt,clips}
fetch "$BUNDLE_SRC" "$WORK/bundle.tar.gz"
fetch "$CUDA_SRC" "$WORK/cuda.tar.gz"
tar -xzf "$WORK/bundle.tar.gz" -C "$WORK/bundle"
tar -xzf "$WORK/cuda.tar.gz" -C "$WORK/cuda"
BUNDLE="$(dirname "$(find "$WORK/bundle" -name whispaste -type f -perm -u+x | head -n1)")"
CUDA_DIR="$(dirname "$(find "$WORK/cuda" -name libggml-cuda.so | head -n1)")"
[[ -f "$BUNDLE/lib/libwhisper.so" ]] || { echo "ERROR: no lib/libwhisper.so in bundle" >&2; exit 1; }
[[ -f "$CUDA_DIR/libggml-cuda.so" ]] || { echo "ERROR: no libggml-cuda.so in CUDA archive" >&2; exit 1; }

echo "=== models ==="
# Same files + SHA-256 as the app's catalog (lib/services/model_download_service.dart).
declare -A MODEL_FILE=(
  [whisper-medium]=ggml-medium-q5_0.bin
  [whisper-large-v3-turbo]=ggml-large-v3-turbo-q5_0.bin
)
declare -A MODEL_SHA=(
  [whisper-medium]=19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f
  [whisper-large-v3-turbo]=394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2
)
for model in $MODELS; do
  file="$WORK/models/stt/${MODEL_FILE[$model]}"
  if [[ ! -f "$file" ]]; then
    fetch "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE[$model]}" "$file"
  fi
  echo "${MODEL_SHA[$model]}  $file" | sha256sum -c -
done

echo "=== clips ==="
# LibriSpeech test-clean (CC BY 4.0, website/scripts/librispeech-sample/)
# concatenated and cut to exactly N seconds of 16 kHz mono 16-bit PCM.
for i in $(seq -w 0 19); do
  fetch "$SAMPLE_BASE/2277-149896-00$i.wav" "$WORK/clips/src-$i.wav"
done
python3 -I - "$WORK/clips" $CLIPS <<'PY'
import glob, os, struct, sys
clip_dir, seconds = sys.argv[1], [int(s) for s in sys.argv[2:]]
pcm = b""
for path in sorted(glob.glob(os.path.join(clip_dir, "src-*.wav"))):
    data = open(path, "rb").read()
    pos = 12
    while pos + 8 <= len(data):
        cid, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if cid == b"data":
            pcm += data[pos + 8:pos + 8 + size]
            break
        pos += 8 + size + (size & 1)
for s in seconds:
    body = pcm[: s * 32000]
    if len(body) < s * 32000:
        sys.exit(f"not enough sample audio for {s} s")
    header = b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16) + b"data" + struct.pack("<I", len(body))
    open(os.path.join(clip_dir, f"clip-{s}s.wav"), "wb").write(header + body)
PY

echo "=== system ==="
VULKAN_OK=0
if vulkaninfo --summary 2>/dev/null | grep -qi nvidia; then VULKAN_OK=1; fi
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader \
  | head -n1 > "$WORK/gpu.csv"
CUDA_VERSION="$(nvidia-smi | grep -o 'CUDA Version: [0-9.]*' | awk '{print $3}')"
python3 -I - "$WORK/gpu.csv" "$CUDA_VERSION" "$VULKAN_OK" > "$OUT/system.json" <<'PY'
import json, sys
name, driver, mem = [p.strip() for p in open(sys.argv[1]).read().split(",")]
print(json.dumps({"gpu": name, "driver": driver, "memoryTotal": mem,
                  "cudaDriverVersion": sys.argv[2],
                  "vulkanAvailable": sys.argv[3] == "1"}, indent=2))
PY
cat "$OUT/system.json"

# The app resolves models under $XDG_CONFIG_HOME/whispaste/models/stt
# (path_service.dart), like headless-benchmark.yml.
export XDG_CONFIG_HOME="$WORK/config"
mkdir -p "$XDG_CONFIG_HOME/whispaste/models"
ln -sfn "$WORK/models/stt" "$XDG_CONFIG_HOME/whispaste/models/stt"

cuda_files() { (cd "$CUDA_DIR" && ls -- *.so*); }
install_cuda() { cp "$CUDA_DIR"/*.so* "$BUNDLE/lib/"; }
remove_cuda() { for f in $(cuda_files); do rm -f "$BUNDLE/lib/$f"; done; }

run() { # <mode> <model> <clip-seconds>
  local mode="$1" model="$2" clip="$3" gpu=auto
  local tag="$mode-$model-${clip}s" peak="$WORK/$mode-$model-${clip}s.vram"
  remove_cuda
  case "$mode" in
    cuda) install_cuda ;;
    cpu) gpu=disabled ;;
  esac
  echo "── $tag"
  nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms 200 > "$peak" &
  local smi=$!
  local rc=0
  timeout 1800 xvfb-run -a dbus-run-session -- "$BUNDLE/whispaste" \
    --transcribe-file "$WORK/clips/clip-${clip}s.wav" --engine whisper \
    --model "$model" --language en --gpu "$gpu" --repeat "$REPEAT" \
    --json --out "$OUT/$tag.json" >/dev/null || rc=$?
  kill "$smi" 2>/dev/null || true
  wait "$smi" 2>/dev/null || true
  python3 -I - "$OUT/$tag.json" "$peak" "$mode" "$rc" <<'PY'
import json, os, sys
path, peak_file, mode, rc = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
report = json.load(open(path)) if os.path.exists(path) else {}
vals = [int(v) for v in open(peak_file).read().split() if v.strip().isdigit()]
report.update({"mode": mode, "exitCode": rc, "vramPeakMiB": max(vals) if vals else None})
json.dump(report, open(path, "w"), indent=2)
print(f"  exit={rc} device={report.get('gpuDevice')} backend={report.get('backend')} "
      f"load={report.get('loadMs')}ms median={report.get('transcribeMsMedian')}ms "
      f"vramPeak={report['vramPeakMiB']}MiB")
PY
}

echo "=== runs (repeat $REPEAT) ==="
for model in $MODELS; do
  for clip in $CLIPS; do
    run cuda "$model" "$clip"
    if [[ "$VULKAN_OK" == 1 ]]; then
      run vulkan "$model" "$clip"
    else
      echo "── vulkan-$model-${clip}s: skipped (no NVIDIA Vulkan ICD in this container)"
    fi
    run cpu "$model" "$clip"
  done
done
remove_cuda

python3 -I - "$OUT" <<'PY'
import glob, json, os, sys
out = sys.argv[1]
system = json.load(open(os.path.join(out, "system.json")))
rows = []
for path in sorted(glob.glob(os.path.join(out, "*-*s.json"))):
    r = json.load(open(path))
    runs = [x["transcribeMs"] for x in r.get("runs", [])]
    expected = {"cuda": "CUDA", "vulkan": "Vulkan", "cpu": None}[r["mode"]]
    device = r.get("gpuDevice")
    ok = r.get("exitCode") == 0 and (
        device is None if expected is None else (device or "").startswith(expected))
    rows.append({
        "mode": r["mode"], "model": r.get("model"),
        "clipMs": r.get("audioDurationMs"), "gpuDevice": device,
        "loadMs": r.get("loadMs"), "transcribeMsMedian": r.get("transcribeMsMedian"),
        "transcribeMsMin": min(runs) if runs else None, "rtfMedian": r.get("rtfMedian"),
        "vramPeakMiB": r.get("vramPeakMiB"), "ok": ok,
    })
json.dump({"system": system, "runs": rows}, open(os.path.join(out, "results.json"), "w"), indent=2)
lines = [
    f"GPU {system['gpu']}, driver {system['driver']}, CUDA {system['cudaDriverVersion']}, "
    f"VRAM {system['memoryTotal']}, Vulkan {'yes' if system['vulkanAvailable'] else 'no'}",
    "",
    "| Modus | Modell | Clip | Gerät | Laden ms | Median ms | Min ms | RTF | VRAM-Spitze MiB | ok |",
    "|---|---|---:|---|---:|---:|---:|---:|---:|---|",
]
for r in rows:
    rtf = f"{r['rtfMedian']:.3f}" if r["rtfMedian"] is not None else "–"
    lines.append(
        f"| {r['mode']} | {r['model']} | {(r['clipMs'] or 0) / 1000:.0f} s | {r['gpuDevice'] or 'CPU'} "
        f"| {r['loadMs']} | {r['transcribeMsMedian']} | {r['transcribeMsMin']} | {rtf} "
        f"| {r['vramPeakMiB']} | {'ja' if r['ok'] else 'NEIN'} |")
open(os.path.join(out, "results.md"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
echo "=== done: $OUT ==="
