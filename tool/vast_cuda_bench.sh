#!/usr/bin/env bash
# vast_cuda_bench.sh — CUDA vs Vulkan vs CPU whisper benchmark on a rented
# NVIDIA GPU (Vast.ai, default RTX 3090), orchestrated entirely from this Mac (handy-catchup
# ticket 13). Runs tool/gpu_bench_vast.sh on the box.
#
# Flow: search offers (free) -> rent -> wait for SSH (6 min) -> if SSH never
# comes up, stop (or with --retry-unreachable: destroy and rent once more on
# another offer) -> rsync the worktree ->
# Flutter Linux bundle, libwhisper (CPU+Vulkan), CUDA module for the box's own
# compute capability (nvcc from the devel image) -> tool/gpu_bench_vast.sh ->
# copy results to ~/whispaste-gpu-bench/<timestamp>/ -> destroy the instance.
# A clean commit reuses an earlier bundle and CUDA module from
# ~/whispaste-gpu-bench/cache/<sha>/ (skips the flutter and libwhisper steps).
#
# GitHub policy (user rule "1a"): the box may download public third-party
# dependencies from github.com, as a normal local build does (CMake FetchContent,
# whisper.cpp, Dart native assets). Forbidden: GitHub Actions or workflows that
# touch Vast, Vast keys on GitHub, downloading this repo's own artifacts or
# releases onto the box, and gh on the box. Our code always comes from the Mac via rsync.
#
# The instance is destroyed on every exit path (EXIT, INT, TERM) and the
# account is checked afterwards. Each remote step has a stamp file on the box,
# so a dropped SSH connection resumes at the same step instead of starting over.
#
# Budget: the run aborts when burn rate x elapsed reaches HARD_BUDGET_USD (2.00)
# or the wall clock reaches min(WALL_CAP_H, 0.9 x HARD_BUDGET_USD / burn rate).
# Burn rate = dph_total + DISK_GB x storage_cost / 730 (per hour).
#
# Usage: tool/vast_cuda_bench.sh [--gpu "<name>"] [--with-cpu] [--search-only] [--out DIR] [--help]
#   --gpu NAME     GPU model to rent, as Vast names it (default "RTX 3090"),
#                  e.g. "RTX 3060", "GTX 1660 Ti", "RTX 2060", "Tesla T4"
#   --with-cpu     also measure the CPU mode (off by default: the rented box's CPU
#                  says nothing about desktop users)
#   --search-only  list the cheapest matching offer and exit (no rent, free)
#   --out DIR      results directory (default ~/whispaste-gpu-bench/<timestamp>)
#   --pack DIR     test an extracted optional CUDA pack (tool/cuda_pack_build.sh)
#                  instead of building the CUDA module: rsynced from this Mac, loaded
#                  by the app via --cuda-pack, plus a corrupted copy that must fall
#                  back to Vulkan
#   --retry-unreachable  if the box never answers SSH, destroy it and rent once
#                  more on another offer (off by default: stop and report instead)
set -euo pipefail

VASTAI="${VASTAI:-$HOME/.local/bin/vastai}"
API_KEY_FILE="$HOME/.config/vastai/vast_api_key"
SSH_KEY="$HOME/.ssh/whispaste-gpu-cloud"
IMAGE="nvidia/cuda:12.8.1-devel-ubuntu24.04"
DISK_GB=64
MIN_RELIABILITY=0.98
HARD_BUDGET_USD=2.00
WALL_CAP_H=3
READY_TIMEOUT_S=360
# Machines that failed the SSH-ready check: 137691 (run 4, SSH never accepted the key).
EXCLUDED_MACHINES="137691"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/whispaste-gpu-bench"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
LABEL="wp-gpubench-$RUN_ID"

SEARCH_ONLY=0
GPU_NAME="RTX 3090"
WITH_CPU=0
PACK_DIR=""
REMOTE_PRELUDE=""
MAX_RENT_ATTEMPTS=1
OUT_DIR=""
INSTANCE_ID=""
SSH_HOST=""
SSH_PORT=""
LOG_FILE=""
BURN=""
DEADLINE_EPOCH=0
START_EPOCH=0
CREDIT_BEFORE=""

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search-only) SEARCH_ONLY=1 ;;
    --with-cpu) WITH_CPU=1 ;;
    --gpu) GPU_NAME="${2:?--gpu needs a name, e.g. \"RTX 3060\"}"; shift ;;
    --retry-unreachable) MAX_RENT_ATTEMPTS=2 ;;
    --out) OUT_DIR="${2:?--out needs a directory}"; shift ;;
    --pack) PACK_DIR="${2:?--pack needs an extracted pack directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

TIMEOUT_BIN="$(command -v gtimeout || command -v timeout || true)"
[[ -n "$TIMEOUT_BIN" ]] || { echo "ERROR: needs GNU timeout (brew install coreutils)" >&2; exit 1; }
[[ -x "$VASTAI" ]] || { echo "ERROR: vastai CLI not found at $VASTAI" >&2; exit 1; }
[[ -f "$API_KEY_FILE" ]] || { echo "ERROR: missing $API_KEY_FILE" >&2; exit 1; }
[[ -f "$SSH_KEY" ]] || { echo "ERROR: missing SSH key $SSH_KEY" >&2; exit 1; }
if [[ -n "$PACK_DIR" ]]; then
  [[ -f "$PACK_DIR/libggml-cuda.so" ]] || { echo "ERROR: no libggml-cuda.so in $PACK_DIR" >&2; exit 1; }
  PACK_DIR="$(cd "$PACK_DIR" && pwd)"
fi

log() {
  local msg
  msg="[$(date +%H:%M:%S)] $*"
  echo "$msg" >&2
  if [[ -n "$LOG_FILE" ]]; then echo "$msg" >> "$LOG_FILE"; fi
}
die() { log "ERROR: $*"; exit 1; }

# Prints the account credit only. The key is passed via process substitution,
# never on the command line or in the log.
credit() {
  curl -s -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$API_KEY_FILE")") \
    https://console.vast.ai/api/v0/users/current/ \
    | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(), strict=False)["credit"])'
}

# Cheapest verified RTX 3090 with direct SSH, reliability > MIN_RELIABILITY,
# >= DISK_GB disk and CUDA >= 12.8 (needed for the devel image's nvcc).
# Prints: <id> <burn USD/h> <gpu> <reliability> <cores> <disk GB>
search_offer() { # [excluded machine ids, space separated]
  local gpu_q="${GPU_NAME// /_}"
  local query="reliability > $MIN_RELIABILITY num_gpus=1 gpu_name=$gpu_q verified=true rentable=true direct_port_count>=1 disk_space>=$DISK_GB cuda_max_good>=12.8"
  "$VASTAI" search offers "$query" -o dph_total --raw 2>/dev/null | python3 -c '
import json, sys
disk = float(sys.argv[1])
excluded = set(sys.argv[2].split())
offers = json.loads(sys.stdin.read(), strict=False)
ok = [o for o in offers
      if o.get("verification") == "verified" and o.get("direct_port_count", 0) >= 1
      and o.get("disk_space", 0) >= disk and str(o.get("machine_id")) not in excluded]
if not ok:
    sys.exit("no matching offer")
def burn(o):
    return o["dph_total"] + disk * o.get("storage_cost", 0) / 730
o = min(ok, key=burn)
print(o["id"], "%.4f" % burn(o), o["gpu_name"].replace(" ", "_"), "%.3f" % o["reliability"],
      o.get("cpu_cores_effective"), int(o["disk_space"]))
' "$DISK_GB" "${1:-}"
}

list_ids() {
  "$VASTAI" show instances --raw 2>/dev/null | python3 -c '
import json, sys
print(" ".join(str(i["id"]) for i in json.loads(sys.stdin.read(), strict=False)))'
}

label_ids() {
  "$VASTAI" show instances --raw 2>/dev/null | python3 -c '
import json, sys
label = sys.argv[1]
print(" ".join(str(i["id"]) for i in json.loads(sys.stdin.read(), strict=False) if i.get("label") == label))' "$LABEL"
}

instance_json() { "$VASTAI" show instance "$1" --raw 2>/dev/null; }

instance_status() {
  instance_json "$1" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(), strict=False).get("actual_status") or "")' 2>/dev/null || true
}

# Prints one line per endpoint: "<direct|proxy> <host> <port>". Direct is the
# port mapping on the host, proxy is the Vast SSH gateway (`vastai ssh-url`).
ssh_endpoints() {
  instance_json "$1" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read(), strict=False)
ports = (d.get("ports") or {}).get("22/tcp") or []
if ports and d.get("public_ipaddr"):
    print("direct", d["public_ipaddr"], ports[0]["HostPort"])
if d.get("ssh_host") and d.get("ssh_port"):
    print("proxy", d["ssh_host"], d["ssh_port"])' 2>/dev/null || true
}

# Maps the stderr of a failed ssh attempt to one class.
classify_ssh_error() {
  case "$1" in
    *"Connection refused"*) echo "connection refused" ;;
    *"timed out"*|*"No route to host"*) echo "timeout" ;;
    *"Permission denied (publickey"*) echo "publickey denied" ;;
    *"Host key verification failed"*|*"REMOTE HOST IDENTIFICATION"*) echo "host key problem" ;;
    *"Connection closed"*|*"Connection reset"*|*"kex_exchange"*) echo "closed during handshake" ;;
    *) echo "other" ;;
  esac
}

set_ssh_opts() {
  SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new
    -o LogLevel=ERROR -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=10
    -p "$SSH_PORT")
}

ssh_cmd() { ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" "$@"; }

rsync_ssh() { echo "ssh -i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR -p $SSH_PORT"; }

remaining() { echo $(( DEADLINE_EPOCH - $(date +%s) )); }

# Aborts when the spend or the wall clock limit is reached.
guard() {
  local now elapsed
  now="$(date +%s)"
  elapsed=$(( now - START_EPOCH ))
  if awk -v b="$BURN" -v e="$elapsed" -v h="$HARD_BUDGET_USD" 'BEGIN { exit !(b * e / 3600 > h) }'; then
    die "budget guard: burn ${BURN} USD/h x ${elapsed}s exceeds ${HARD_BUDGET_USD} USD"
  fi
  if (( now >= DEADLINE_EPOCH )); then
    die "wall-clock guard: deadline reached after ${elapsed}s"
  fi
}

# Returns 1 when SSH does not come up within READY_TIMEOUT_S.
# Polls both endpoints until one answers (returns 0, logs which one won) or
# READY_TIMEOUT_S passes (collects diagnostics, returns 1). Every failed attempt
# is classified and appended to logs/ssh-wait.log.
wait_ready() {
  local t0 st kind host port err found
  local wait_log="$OUT_DIR/logs/ssh-wait.log"
  t0="$(date +%s)"
  while :; do
    guard
    st="$(instance_status "$INSTANCE_ID")"
    found=0
    if [[ "$st" == "running" ]]; then
      while read -r kind host port; do
        [[ -n "$kind" ]] || continue
        found=1
        SSH_HOST="$host"
        SSH_PORT="$port"
        set_ssh_opts
        if err="$(ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" true </dev/null 2>&1)"; then
          log "SSH reachable via $kind endpoint: root@$SSH_HOST:$SSH_PORT"
          return 0
        fi
        echo "$(date +%H:%M:%S) $kind $host:$port: $(classify_ssh_error "$err"): $(printf '%s' "$err" | tail -n 1)" >> "$wait_log"
      done < <(ssh_endpoints "$INSTANCE_ID")
    fi
    if [[ "$found" == 0 ]]; then
      echo "$(date +%H:%M:%S) no endpoint yet (status: ${st:-unknown})" >> "$wait_log"
    fi
    if (( $(date +%s) - t0 >= READY_TIMEOUT_S )); then
      log "instance not reachable after ${READY_TIMEOUT_S}s (status: ${st:-unknown}), collecting diagnostics before destroy"
      collect_diagnostics
      return 1
    fi
    sleep 15
  done
}

# Saves diagnostics for an unreachable instance. Keys and api tokens are redacted.
collect_diagnostics() {
  local dir="$OUT_DIR/diagnostics" kind host port
  mkdir -p "$dir"
  "$VASTAI" logs "$INSTANCE_ID" > "$dir/instance-logs.txt" 2>&1 || true
  instance_json "$INSTANCE_ID" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read(), strict=False)
secret = ("key", "token", "password", "secret", "api")
def clean(o):
    if isinstance(o, dict):
        return {k: ("REDACTED" if isinstance(v, str) and v and any(x in k.lower() for x in secret) else clean(v))
                for k, v in o.items()}
    if isinstance(o, list):
        return [clean(x) for x in o]
    return o
json.dump(clean(d), sys.stdout, indent=1)' > "$dir/instance.json" 2>/dev/null || true
  "$VASTAI" show ssh-keys --raw > "$dir/ssh-keys.json" 2>/dev/null || true
  if grep -q "$(awk "{print \$2}" "$SSH_KEY.pub")" "$dir/ssh-keys.json" 2>/dev/null; then
    log "account SSH key: present in vastai show ssh-keys"
  else
    log "account SSH key: NOT found in vastai show ssh-keys"
  fi
  while read -r kind host port; do
    [[ -n "$kind" ]] || continue
    SSH_HOST="$host"
    SSH_PORT="$port"
    set_ssh_opts
    ssh -v "${SSH_OPTS[@]}" "root@$SSH_HOST" true </dev/null > "$dir/ssh-verbose-$kind.log" 2>&1 || true
  done < <(ssh_endpoints "$INSTANCE_ID")
  log "diagnostics saved to $dir"
}

# Runs one remote step. The step body comes on stdin; it is wrapped with a
# stamp check (skip if already done) and a stamp on success. A lost SSH
# connection (exit 255) reconnects and re-runs the step; other failures abort.
remote_step() { # <name>
  local name="$1" body="$OUT_DIR/steps/$1.sh" logf="$OUT_DIR/logs/$1.log" attempt rc
  {
    printf 'set -euo pipefail\nexport DEBIAN_FRONTEND=noninteractive\n'
    printf 'export PATH=/opt/flutter/bin:/usr/local/cuda/bin:$PATH\n'
    printf '%s\n' "${REMOTE_PRELUDE:-}"
    printf 'mkdir -p /opt/wp-state\n'
    printf 'if [ -f /opt/wp-state/%s.done ]; then echo "== %s: already done"; exit 0; fi\n' "$name" "$name"
    cat
    printf '\ntouch /opt/wp-state/%s.done\necho "== %s: ok"\n' "$name" "$name"
  } > "$body"
  for attempt in 1 2 3; do
    guard
    log "step $name (attempt $attempt) started"
    rc=0
    "$TIMEOUT_BIN" "$(remaining)" ssh "${SSH_OPTS[@]}" "root@$SSH_HOST" \
      "mkdir -p /opt/wp-state && cat > /opt/wp-state/$name.sh && bash /opt/wp-state/$name.sh" \
      < "$body" >> "$logf" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then
      log "step $name: ok"
      return 0
    fi
    if [[ $rc -ne 255 ]]; then
      tail -n 40 "$logf" >&2
      die "step $name failed (exit $rc), full log: $logf"
    fi
    log "step $name: SSH connection lost, reconnecting"
    wait_ready || die "step $name: instance unreachable"
  done
  die "step $name: connection kept failing"
}

# Copies a local directory to /opt/wp-src/<path> on the box, or back.
push_dir() { # <local dir> <path under /opt/wp-src>
  ssh_cmd "mkdir -p /opt/wp-src/$2"
  rsync -az -e "$(rsync_ssh)" "$1" "root@$SSH_HOST:/opt/wp-src/$2"
}
pull_dir() { # <path under /opt/wp-src> <local dir>
  mkdir -p "$2"
  rsync -az -e "$(rsync_ssh)" "root@$SSH_HOST:/opt/wp-src/$1" "$2"
}
# Fills a cache entry atomically: an interrupted pull never leaves a partial entry.
cache_store() { # <path under /opt/wp-src> <cache dir>
  local tmp="$2.partial"
  rm -rf "$tmp"
  pull_dir "$1" "$tmp" && rm -rf "$2" && mv "$tmp" "$2"
}

sync_sources() {
  local rsh; rsh="$(rsync_ssh)"
  # Worktree without VCS metadata and bulky build/cache folders.
  rsync -az --delete -e "$rsh" \
    --exclude=/.git --exclude=/.build/ --exclude=/build/ --exclude=/.dart_tool/ \
    --exclude=/internal-notes --exclude=/website/node_modules/ --exclude=/website/dist/ \
    --exclude=/website/.astro/ --exclude=/ios/Pods/ --exclude=/macos/Pods/ --exclude=/.gradle/ \
    "$REPO_ROOT/" "root@$SSH_HOST:/opt/wp-src/"

}

destroy_instance() { # <id>
  local id="$1"
  for _ in 1 2 3 4; do
    "$VASTAI" destroy instance "$id" -y >/dev/null 2>&1
    sleep 3
    case " $(list_ids) " in *" $id "*) ;; *) return 0 ;; esac
  done
  return 1
}

cleanup() {
  local rc=$? id left credit_after
  trap - EXIT INT TERM
  set +e
  if [[ -z "$INSTANCE_ID" ]]; then
    INSTANCE_ID="$(label_ids | awk '{print $1}')"
  fi
  if [[ -n "$INSTANCE_ID" ]]; then
    for id in $INSTANCE_ID; do destroy_instance "$id"; done
  fi
  left="$(list_ids)"
  if [[ -z "$left" ]]; then
    log "verified: vastai show instances is empty"
  else
    log "WARNING: instances still listed (not touched if not ours): $left"
  fi
  if [[ -n "$CREDIT_BEFORE" ]]; then
    credit_after="$(credit 2>/dev/null)"
    log "credit before: $CREDIT_BEFORE USD, after: ${credit_after:-unknown} USD"
  fi
  exit "$rc"
}

main() {
  local offer
  offer="$(search_offer)" || die "no matching RTX 3090 offer"
  set -- $offer
  local offer_id="$1" burn="$2" gpu="$3" rel="$4" cores="$5" disk="$6"
  log "gpu model: $GPU_NAME"
  log "cheapest match: offer $offer_id, $gpu, reliability $rel, $cores cores, ${disk} GB, burn ${burn} USD/h"
  if [[ "$SEARCH_ONLY" == 1 ]]; then
    exit 0
  fi

  OUT_DIR="${OUT_DIR:-$STATE_DIR/$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$OUT_DIR/logs" "$OUT_DIR/steps"
  LOG_FILE="$OUT_DIR/run.log"
  BURN="$burn"
  CREDIT_BEFORE="$(credit)"
  log "credit before: $CREDIT_BEFORE USD"

  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  START_EPOCH="$(date +%s)"
  DEADLINE_EPOCH="$(awk -v cap="$WALL_CAP_H" -v hb="$HARD_BUDGET_USD" -v b="$BURN" -v s="$START_EPOCH" \
    'BEGIN { w = cap * 3600; x = 0.9 * hb / b * 3600; printf "%d", s + (x < w ? x : w) }')"
  log "limits: spend <= $HARD_BUDGET_USD USD, wall clock <= $(( (DEADLINE_EPOCH - START_EPOCH) / 60 )) min"

  local attempt=1 machine
  while :; do
    log "renting offer $offer_id ($gpu, burn ${burn} USD/h), attempt $attempt"
    "$VASTAI" create instance "$offer_id" --image "$IMAGE" --disk "$DISK_GB" --ssh --direct \
      --env '-e NVIDIA_DRIVER_CAPABILITIES=all -e NVIDIA_VISIBLE_DEVICES=all' \
      --label "$LABEL" --raw > "$OUT_DIR/create.json" 2>>"$LOG_FILE" || die "create instance failed (see $OUT_DIR/create.json)"
    INSTANCE_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("new_contract") or "")' "$OUT_DIR/create.json")"
    python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop("instance_api_key", None); json.dump(d, open(p, "w"), indent=1)' "$OUT_DIR/create.json"
    [[ -n "$INSTANCE_ID" ]] || die "no instance id in $OUT_DIR/create.json"
    log "instance $INSTANCE_ID rented (label $LABEL), waiting for SSH"
    if wait_ready; then
      break
    fi
    (( attempt < MAX_RENT_ATTEMPTS )) || die "instance unreachable after $attempt attempt(s), see $OUT_DIR/diagnostics"
    machine="$(instance_json "$INSTANCE_ID" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read(), strict=False).get("machine_id") or "")' 2>/dev/null || true)"
    destroy_instance "$INSTANCE_ID" || die "could not destroy $INSTANCE_ID"
    log "destroyed $INSTANCE_ID, machine ${machine:-unknown} excluded; retrying on another offer"
    EXCLUDED_MACHINES="$EXCLUDED_MACHINES ${machine:-}"
    INSTANCE_ID=""
    offer="$(search_offer "$EXCLUDED_MACHINES")" || die "no alternative RTX 3090 offer"
    set -- $offer
    offer_id="$1" burn="$2" gpu="$3" rel="$4" cores="$5" disk="$6"
    BURN="$(awk -v a="$BURN" -v b="$burn" 'BEGIN { print (b > a ? b : a) }')"
    attempt=$(( attempt + 1 ))
  done

  remote_step prep <<'STEP'
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  ca-certificates curl git rsync python3 xz-utils unzip \
  clang cmake ninja-build pkg-config g++ patchelf binutils \
  libgtk-3-dev liblzma-dev libsecret-1-dev libkeybinder-3.0-dev libnotify-dev \
  libayatana-appindicator3-dev libasound2-dev libxss-dev libcurl4-openssl-dev zlib1g-dev \
  libflac-dev libogg-dev libopus-dev libvorbis-dev default-jdk \
  libvulkan-dev glslang-tools glslc spirv-headers >/dev/null
git config --global --add safe.directory '*'
if [ ! -x /opt/flutter/bin/flutter ]; then
  curl -fsSL --retry 3 -o /opt/flutter.tar.xz \
    https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz
  tar -xJf /opt/flutter.tar.xz -C /opt
  rm -f /opt/flutter.tar.xz
fi
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --linux
flutter --version >/dev/null
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
STEP

  sync_sources

  # Build cache: a clean commit reuses its Flutter bundle and its CUDA module
  # (per GPU architecture) from an earlier run on this Mac.
  local sha="" cache="" cap cuda_cache=""
  if [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    # Keyed by the last commit outside tool/ and website/: script tweaks keep the cache.
    sha="$(git -C "$REPO_ROOT" log -1 --format=%h --abbrev=12 -- . ':(exclude)tool' ':(exclude)website')"
    cache="$STATE_DIR/cache/$sha"
  else
    log "worktree has uncommitted changes: build cache disabled"
  fi

  if [[ -n "$cache" && -x "$cache/bundle/whispaste" && -f "$cache/bundle/lib/libggml-vulkan.so" ]]; then
    log "build cache hit: Flutter bundle for $sha"
    push_dir "$cache/bundle/" build/linux/x64/release/bundle/
    ssh_cmd "mkdir -p /opt/wp-state && touch /opt/wp-state/flutter.done /opt/wp-state/libwhisper_cpu_vulkan.done"
  else
    remote_step flutter <<'STEP'
cd /opt/wp-src
export TRY_SYSTEM_LIBS_FIRST=1
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"
flutter pub get
flutter build linux --release --no-tree-shake-icons
ls build/linux/x64/release/bundle/whispaste
STEP

    remote_step libwhisper_cpu_vulkan <<'STEP'
cd /opt/wp-src
if [ ! -d .build/deps/whisper.cpp/v1.9.5 ]; then
  git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.9.5
fi
BUILD_JOBS="$(nproc)" bash scripts/build-libwhisper-linux.sh
mkdir -p build/linux/x64/release/bundle/lib
cp .build/libwhisper/linux/*.so* build/linux/x64/release/bundle/lib/
cp assets/models/vad/ggml-silero-v5.1.2.bin build/linux/x64/release/bundle/lib/
ls build/linux/x64/release/bundle/lib
STEP
    if [[ -n "$cache" ]]; then
      cache_store build/linux/x64/release/bundle/ "$cache/bundle"
    fi
  fi

  if [[ -n "$PACK_DIR" ]]; then
    log "pack mode: pushing $(basename "$PACK_DIR") instead of building the CUDA module"
    push_dir "$PACK_DIR/" .build/cuda-pack/
    REMOTE_PRELUDE="export BENCH_WITH_CPU=$WITH_CPU BENCH_PACK=/opt/wp-src/.build/cuda-pack"
    remote_step bench <<'STEP'
cd /opt/wp-src
bash tool/gpu_bench_vast.sh build/linux/x64/release/bundle .build/cuda-pack /opt/wp-bench/results
STEP
    REMOTE_PRELUDE=""
    fetch_results
    return
  fi

  # CUDA module for this box's GPU only (its compute capability, e.g. 86 -> sm_86).
  cap="$(ssh_cmd nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n 1 | tr -d '.' || true)"
  [[ "$cap" =~ ^[0-9]+$ ]] || die "could not read the GPU compute capability: '$cap'"
  log "GPU compute capability $cap: building the CUDA module for sm_$cap only"
  [[ -n "$cache" ]] && cuda_cache="$cache/linux-cuda-$cap"
  if [[ -n "$cuda_cache" && -f "$cuda_cache/libggml-cuda.so" ]]; then
    log "build cache hit: CUDA module for sm_$cap"
    push_dir "$cuda_cache/" .build/libwhisper/linux-cuda/
    ssh_cmd "mkdir -p /opt/wp-state && touch /opt/wp-state/libwhisper_cuda.done"
  else
    REMOTE_PRELUDE="export CUDA_ARCHS=${cap}-real"
    remote_step libwhisper_cuda <<'STEP'
cd /opt/wp-src
export CUDA_HOME=/usr/local/cuda CUDACXX=/usr/local/cuda/bin/nvcc
export PATH=/usr/local/cuda/bin:$PATH
nvcc --version | tail -n 1
# The source is missing when the bundle came from the build cache.
if [ ! -d .build/deps/whisper.cpp/v1.9.5 ]; then
  git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp .build/deps/whisper.cpp/v1.9.5
fi
jobs="$(nproc)"; if [ "$jobs" -gt 8 ]; then jobs=8; fi
BUILD_JOBS="$jobs" bash scripts/build-libwhisper-linux.sh --cuda
STEP
    REMOTE_PRELUDE=""
    if [[ -n "$cuda_cache" ]]; then
      cache_store .build/libwhisper/linux-cuda/ "$cuda_cache"
    fi
  fi

  REMOTE_PRELUDE="export BENCH_WITH_CPU=$WITH_CPU"
  remote_step bench <<'STEP'
cd /opt/wp-src
bash tool/gpu_bench_vast.sh build/linux/x64/release/bundle .build/libwhisper/linux-cuda /opt/wp-bench/results
STEP
  REMOTE_PRELUDE=""
  fetch_results
}

fetch_results() {
  mkdir -p "$OUT_DIR/results"
  rsync -az -e "$(rsync_ssh)" "root@$SSH_HOST:/opt/wp-bench/results/" "$OUT_DIR/results/"
  log "results copied to $OUT_DIR/results"
  if [[ -f "$OUT_DIR/results/results.md" ]]; then
    cat "$OUT_DIR/results/results.md"
  fi
}

main "$@"
