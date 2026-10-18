#!/usr/bin/env bash
# cuda_pack_build.sh — Mac-side driver for the optional CUDA backend packs.
#
# Builds both packs side by side and copies the archives to
# ~/whispaste-cuda-packs/<packId>/ together with a manifest.json:
#   - Windows natively on SilviosPC (SSH + PowerShell, detached via WMI)
#   - Linux in an ubuntu:24.04 Docker container on local-ai-srv (glibc 2.39 =
#     the release baseline; the host's own glibc is newer). No GPU is needed:
#     the CUDA toolkit comes from NVIDIA redist archives, nothing runs on a GPU.
# Archives are read in place (never extracted) for the manifest.
#
# Usage:   tool/cuda_pack_build.sh [--fetch-only | --linux-only]
#   --fetch-only      skip the builds; only copy and describe packs already built
#   --linux-only      build and fetch only the Linux pack (no SilviosPC needed)
#   WINBOX=<host|ip>  default silviospc.local (mDNS is flaky; win-test/find-winbox.sh
#                     resolves the current DHCP address)
#   LINUX_HOST=<ssh>  default local-ai-srv (needs Docker and passwordless SSH)
#   DOCKER_IMAGE=<i>  default ubuntu:24.04
#   BUILD_JOBS=<n>    jobs per build, default 4 (8 would suit the Linux host)
#
# Remote layout: C:\wp-cuda-build\{scripts,out,src,cuda,build,...} on the box;
# ~/wp-cuda-build/{scripts,out,work,...} on LINUX_HOST (work = build cache).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINBOX="${WINBOX:-silviospc.local}"
WIN_USER="silvi"
LINUX_HOST="${LINUX_HOST:-local-ai-srv}"
DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:24.04}"
LX_DIR="wp-cuda-build"   # relative to the remote home
BUILD_JOBS="${BUILD_JOBS:-4}"
KEY="$HOME/.ssh/whispaste-winbox"
PACK_ROOT="$HOME/whispaste-cuda-packs"
WIN_PACK_ID="WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64"
LINUX_PACK_ID="WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64"
FETCH_ONLY=0
LINUX_ONLY=0
case "${1:-}" in
  --fetch-only) FETCH_ONLY=1 ;;
  --linux-only) LINUX_ONLY=1 ;;
  "") ;;
  *) echo "usage: $0 [--fetch-only | --linux-only]" >&2; exit 2 ;;
esac

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
SSH=(ssh "${SSH_OPTS[@]}" "$WIN_USER@$WINBOX")
SCP=(scp "${SSH_OPTS[@]}")
LX_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)
LX_SSH=(ssh "${LX_SSH_OPTS[@]}" "$LINUX_HOST")
LX_SCP=(scp -q "${LX_SSH_OPTS[@]}")
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# Runs a PowerShell snippet on the box. Sent base64-encoded so no quoting
# reaches the remote shell.
ps() {
  local encoded
  encoded="$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')"
  "${SSH[@]}" "powershell -NoProfile -NonInteractive -EncodedCommand $encoded"
}

# Starts a command detached through WMI, so it survives the SSH session
# (infrastructure/windows-silviospc.md). The command line must not contain quotes.
launch_detached() {
  local rv
  rv="$(ps "(Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '$1' }).ReturnValue")"
  [[ "$(tr -d '\r' <<<"$rv" | tail -n1)" == "0" ]] || die "could not start detached: $1"
}

# Reads the pack archive and writes manifest.json. Runs with -I; the archive is
# only streamed, never extracted, and SHA256SUMS is checked against the content.
write_manifest() {
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import hashlib, json, os, sys, tarfile, zipfile

archive, platform, pack_id, out_path = sys.argv[1:5]


def digest(stream, keep=False):
    sha, size, kept = hashlib.sha256(), 0, []
    for chunk in iter(lambda: stream.read(1 << 20), b""):
        sha.update(chunk)
        size += len(chunk)
        if keep:
            kept.append(chunk)
    return size, sha.hexdigest(), b"".join(kept)


def members(path):
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                with zf.open(info) as f:
                    yield (info.filename,) + digest(f, info.filename == "SHA256SUMS")
    else:
        with tarfile.open(path, "r:gz") as tf:
            for m in tf.getmembers():
                if not m.isfile():
                    continue
                with tf.extractfile(m) as f:
                    yield (m.name,) + digest(f, m.name == "SHA256SUMS")


files, sums_bytes = [], None
for name, size, sha, data in members(archive):
    if "/" in name or "\\" in name:
        sys.exit("nested path inside the pack: " + name)
    files.append({"name": name, "size": size, "sha256": sha})
    if data is not None:
        sums_bytes = data
if sums_bytes is None:
    sys.exit("SHA256SUMS missing from the pack")

recorded = {}
for line in sums_bytes.decode("utf-8").splitlines():
    sha, _, name = line.partition("  ")
    recorded[name] = sha
others = {f["name"]: f["sha256"] for f in files if f["name"] != "SHA256SUMS"}
if recorded != others:
    sys.exit("SHA256SUMS does not match the pack content")

with open(archive, "rb") as fh:
    archive_size, archive_sha, _ = digest(fh)
manifest = {
    "packId": pack_id,
    "platform": platform,
    "file": os.path.basename(archive),
    "sizeBytes": archive_size,
    "sha256": archive_sha,
    "unpackedBytes": sum(f["size"] for f in files),
    "files": sorted(files, key=lambda f: f["name"]),
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
print(json.dumps({k: manifest[k] for k in ("file", "sizeBytes", "sha256", "unpackedBytes")}, indent=2))
PY
}

# Copies one finished pack (from the box or LINUX_HOST) and writes its manifest.
fetch_pack() {
  local pack_id="$1" platform="$2" file="$3"
  local dest="$PACK_ROOT/$pack_id"
  mkdir -p "$dest"
  if [[ "$platform" == linux-* ]]; then
    "${LX_SCP[@]}" "$LINUX_HOST:$LX_DIR/out/$file" "$dest/$file" \
      || die "$file not on $LINUX_HOST (build failed?)"
  else
    "${SCP[@]}" "$WIN_USER@$WINBOX:C:/wp-cuda-build/out/$file" "$dest/$file" \
      || die "$file not on the box (build failed?)"
  fi
  write_manifest "$dest/$file" "$platform" "$pack_id" "$dest/manifest.json"
  echo "-> $dest"
}

[[ -f "$KEY" ]] || die "SSH key missing: $KEY"
if [[ "$LINUX_ONLY" == 0 ]]; then
  echo "== reach $WINBOX"
  ps '(Get-CimInstance Win32_OperatingSystem).Caption' >/dev/null \
    || die "$WINBOX not reachable (box off? try WINBOX=<ip>, or win-test/wait-for-winbox.sh)"
fi
echo "== reach $LINUX_HOST"
"${LX_SSH[@]}" 'docker --version' >/dev/null \
  || die "$LINUX_HOST not reachable or Docker missing"

if [[ "$FETCH_ONLY" == 0 ]]; then
  # Linux: one container does apt deps + build; the done marker carries the exit code.
  echo "== sync Linux build scripts -> $LINUX_HOST:$LX_DIR"
  "${LX_SSH[@]}" "mkdir -p $LX_DIR/scripts $LX_DIR/out $LX_DIR/work"
  "${LX_SCP[@]}" \
    "$REPO_ROOT/scripts/build-cuda-pack-linux.sh" \
    "$REPO_ROOT/scripts/fetch-cuda-redist.py" \
    "$REPO_ROOT/scripts/cuda-pack-NOTICE.template.txt" \
    "$LINUX_HOST:$LX_DIR/scripts/"
  cat > "$TMP_DIR/run-linux.sh" <<'SH'
#!/usr/bin/env bash
# Runs on LINUX_HOST, detached. Files created in the container are chowned back
# to the invoking user so later cleanup and scp need no root.
cd "$HOME/wp-cuda-build" || exit 1
rm -f build-linux.done
docker run --rm -v "$PWD:/w" -e BUILD_JOBS="$1" -e OUT_DIR=/w/out -e WORK_DIR=/w/work \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" "$2" bash -c '
    bash /w/scripts/build-cuda-pack-linux.sh --install-deps && bash /w/scripts/build-cuda-pack-linux.sh
    rc=$?; chown -R "$HOST_UID:$HOST_GID" /w; exit $rc' > build-linux.log 2>&1
echo "DONE_RC=$?" > build-linux.done
SH
  "${LX_SCP[@]}" "$TMP_DIR/run-linux.sh" "$LINUX_HOST:$LX_DIR/run-linux.sh"
  "${LX_SSH[@]}" "chmod +x $LX_DIR/run-linux.sh && cd $LX_DIR && rm -f build-linux.done && nohup ./run-linux.sh $BUILD_JOBS $DOCKER_IMAGE >/dev/null 2>&1 < /dev/null &"
  echo "== Linux build started in $DOCKER_IMAGE on $LINUX_HOST (jobs $BUILD_JOBS)"

  if [[ "$LINUX_ONLY" == 0 ]]; then
    echo "== sync Windows build scripts"
    ps 'New-Item -ItemType Directory -Force -Path C:\wp-cuda-build\scripts, C:\wp-cuda-build\out | Out-Null'
    "${SCP[@]}" \
      "$REPO_ROOT/scripts/build-cuda-pack-windows.ps1" \
      "$REPO_ROOT/scripts/fetch-cuda-redist.py" \
      "$REPO_ROOT/scripts/cuda-pack-NOTICE.template.txt" \
      "$WIN_USER@$WINBOX:C:/wp-cuda-build/scripts/"

    echo "== prerequisites (Python 3 via winget if missing)"
    ps 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\wp-cuda-build\scripts\build-cuda-pack-windows.ps1 -InstallPrereqs'

    echo "== start Windows build detached (jobs $BUILD_JOBS)"
    ps 'Remove-Item C:\wp-cuda-build\build-windows.done -ErrorAction SilentlyContinue'
    launch_detached "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\\wp-cuda-build\\scripts\\build-cuda-pack-windows.ps1 -BuildJobs $BUILD_JOBS"
  fi

  echo "== waiting for done markers (polls every 2 min, up to 6 h)"
  # shellcheck disable=SC2016 # PowerShell variables, expanded on the box
  win_poll='$p = "C:\wp-cuda-build\build-windows.done"; if (Test-Path $p) { (Get-Content $p -Raw).Trim() } else { "running" }'
  deadline=$(( SECONDS + 6 * 3600 ))
  while :; do
    lin="$("${LX_SSH[@]}" "cat $LX_DIR/build-linux.done 2>/dev/null || echo running" | tr -d '\r')"
    if [[ "$LINUX_ONLY" == 1 ]]; then win="skipped"; else win="$(ps "$win_poll" | tr -d '\r' | tail -n1)"; fi
    echo "$(date '+%H:%M:%S') windows=$win linux=$lin"
    [[ "$win" != running && "$lin" != running ]] && break
    (( SECONDS < deadline )) || die "timed out waiting for the builds"
    sleep 120
  done
  if [[ "$LINUX_ONLY" == 0 && "$win" != "DONE_RC=0" ]]; then
    ps 'Get-Content C:\wp-cuda-build\build-windows.log -Tail 40' >&2 || true
    die "Windows build failed"
  fi
  if [[ "$lin" != "DONE_RC=0" ]]; then
    "${LX_SSH[@]}" "tail -n 40 $LX_DIR/build-linux.log" >&2 || true
    die "Linux build failed"
  fi
fi

echo "== fetch packs -> $PACK_ROOT"
if [[ "$LINUX_ONLY" == 0 ]]; then fetch_pack "$WIN_PACK_ID" windows-x64 "$WIN_PACK_ID.zip"; fi
fetch_pack "$LINUX_PACK_ID" linux-x64 "$LINUX_PACK_ID.tar.gz"
echo "== done"
