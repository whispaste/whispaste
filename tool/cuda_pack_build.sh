#!/usr/bin/env bash
# cuda_pack_build.sh — Mac-side driver for the optional CUDA backend packs.
#
# Syncs the pack build scripts to SilviosPC, starts both builds detached there
# (Windows natively, Linux inside WSL2 Ubuntu 24.04), waits for their done
# markers, and copies the archives to ~/whispaste-cuda-packs/<packId>/ together
# with a manifest.json. Archives are read in place (never extracted) for the
# manifest. Only SSH and PowerShell are used on the box; no GUI automation.
#
# Usage:   tool/cuda_pack_build.sh [--fetch-only]
#   --fetch-only      skip the builds; only copy and describe packs already built
#   WINBOX=<host|ip>  default silviospc.local (mDNS is flaky; win-vm/find-winbox.sh
#                     resolves the current DHCP address)
#   WSL_DISTRO=<name> default Ubuntu-24.04
#   BUILD_JOBS=<n>    jobs per build, default 4 (both builds run side by side)
#
# Remote layout: C:\wp-cuda-build\{scripts,out,src,cuda,build,...}; the Linux
# build works in ~/wp-cuda-build inside WSL and writes its archive to
# C:\wp-cuda-build\out via /mnt/c.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINBOX="${WINBOX:-silviospc.local}"
WIN_USER="silvi"
WSL_DISTRO="${WSL_DISTRO:-Ubuntu-24.04}"
BUILD_JOBS="${BUILD_JOBS:-4}"
KEY="$HOME/.ssh/whispaste-winbox"
PACK_ROOT="$HOME/whispaste-cuda-packs"
WIN_PACK_ID="WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64"
LINUX_PACK_ID="WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64"
FETCH_ONLY=0
if [[ "${1:-}" == "--fetch-only" ]]; then FETCH_ONLY=1; fi

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
SSH=(ssh "${SSH_OPTS[@]}" "$WIN_USER@$WINBOX")
SCP=(scp "${SSH_OPTS[@]}")
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

# Copies one finished pack from the box and writes its manifest.
fetch_pack() {
  local pack_id="$1" platform="$2" file="$3"
  local dest="$PACK_ROOT/$pack_id"
  mkdir -p "$dest"
  "${SCP[@]}" "$WIN_USER@$WINBOX:C:/wp-cuda-build/out/$file" "$dest/$file" \
    || die "$file not on the box (build failed?)"
  write_manifest "$dest/$file" "$platform" "$pack_id" "$dest/manifest.json"
  echo "-> $dest"
}

[[ -f "$KEY" ]] || die "SSH key missing: $KEY"
echo "== reach $WINBOX"
ps '(Get-CimInstance Win32_OperatingSystem).Caption' >/dev/null \
  || die "$WINBOX not reachable (box off? try WINBOX=<ip>, or win-vm/wait-for-winbox.sh)"

if [[ "$FETCH_ONLY" == 0 ]]; then
  echo "== sync build scripts"
  ps 'New-Item -ItemType Directory -Force -Path C:\wp-cuda-build\scripts, C:\wp-cuda-build\out | Out-Null'
  "${SCP[@]}" \
    "$REPO_ROOT/scripts/build-cuda-pack-windows.ps1" \
    "$REPO_ROOT/scripts/build-cuda-pack-linux.sh" \
    "$REPO_ROOT/scripts/fetch-cuda-redist.py" \
    "$REPO_ROOT/scripts/cuda-pack-NOTICE.template.txt" \
    "$WIN_USER@$WINBOX:C:/wp-cuda-build/scripts/"

  echo "== prerequisites (Python 3 via winget if missing)"
  ps 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\wp-cuda-build\scripts\build-cuda-pack-windows.ps1 -InstallPrereqs'

  echo "== WSL $WSL_DISTRO: build packages (root)"
  "${SSH[@]}" "wsl.exe -d $WSL_DISTRO -u root -- bash /mnt/c/wp-cuda-build/scripts/build-cuda-pack-linux.sh --install-deps" \
    || die "WSL package install failed (is distro '$WSL_DISTRO' present?)"

  # Hidden PowerShell wrapper: runs the Linux build and writes its done marker.
  cat > "$TMP_DIR/run-linux.ps1" <<'PS'
& wsl.exe -d @DISTRO@ -- env BUILD_JOBS=@JOBS@ OUT_DIR=/mnt/c/wp-cuda-build/out bash /mnt/c/wp-cuda-build/scripts/build-cuda-pack-linux.sh *> C:\wp-cuda-build\build-linux.log
"DONE_RC=$LASTEXITCODE" | Out-File -FilePath C:\wp-cuda-build\build-linux.done -Encoding ascii
PS
  sed -e "s/@DISTRO@/$WSL_DISTRO/" -e "s/@JOBS@/$BUILD_JOBS/" "$TMP_DIR/run-linux.ps1" > "$TMP_DIR/run-linux.ps1.new"
  mv "$TMP_DIR/run-linux.ps1.new" "$TMP_DIR/run-linux.ps1"
  "${SCP[@]}" "$TMP_DIR/run-linux.ps1" "$WIN_USER@$WINBOX:C:/wp-cuda-build/run-linux.ps1"

  echo "== start both builds detached (jobs $BUILD_JOBS each)"
  ps 'Remove-Item C:\wp-cuda-build\build-*.done -ErrorAction SilentlyContinue'
  launch_detached "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\\wp-cuda-build\\scripts\\build-cuda-pack-windows.ps1 -BuildJobs $BUILD_JOBS"
  launch_detached "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\\wp-cuda-build\\run-linux.ps1"

  echo "== waiting for done markers (polls every 2 min, up to 6 h)"
  # shellcheck disable=SC2016 # PowerShell variables, expanded on the box
  poll_snippet='foreach ($m in "windows", "linux") { $p = "C:\wp-cuda-build\build-$m.done"; $s = if (Test-Path $p) { (Get-Content $p -Raw).Trim() } else { "running" }; "$m $s" }'
  deadline=$(( SECONDS + 6 * 3600 ))
  while :; do
    states="$(ps "$poll_snippet" | tr -d '\r')"
    echo "$(date '+%H:%M:%S') $(tr '\n' ' ' <<<"$states")"
    grep -q 'running' <<<"$states" || break
    (( SECONDS < deadline )) || die "timed out waiting for the builds"
    sleep 120
  done
  if ! grep -q '^windows DONE_RC=0' <<<"$states"; then
    ps 'Get-Content C:\wp-cuda-build\build-windows.log -Tail 40' >&2 || true
    die "Windows build failed"
  fi
  if ! grep -q '^linux DONE_RC=0' <<<"$states"; then
    ps 'Get-Content C:\wp-cuda-build\build-linux.log -Tail 40' >&2 || true
    die "Linux build failed"
  fi
fi

echo "== fetch packs -> $PACK_ROOT"
fetch_pack "$WIN_PACK_ID" windows-x64 "$WIN_PACK_ID.zip"
fetch_pack "$LINUX_PACK_ID" linux-x64 "$LINUX_PACK_ID.tar.gz"
echo "== done"
