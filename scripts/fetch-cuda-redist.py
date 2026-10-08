#!/usr/bin/env python3
"""fetch-cuda-redist.py — install a minimal CUDA toolkit from NVIDIA's
redistributable archives, for building ggml's CUDA backend in CI.

The full CUDA installer is several GB and needs admin rights; ggml-cuda only
needs nvcc, the runtime, cuBLAS and the header-only CCCL. Upstream
whisper.cpp's Windows CUDA job installs the same component set from
https://developer.download.nvidia.com/compute/cuda/redist (see
.github/workflows/build-cuda-backend.yml). Every archive is checked against
the SHA-256 published in NVIDIA's redistrib_<version>.json manifest before it
is unpacked; the archives' top-level directories are merged into <dest>, so
<dest> ends up shaped like a regular toolkit install (bin/, include/, lib/…).

Usage:
  python3 scripts/fetch-cuda-redist.py <version> <linux-x86_64|windows-x86_64> <dest>
e.g.
  python3 scripts/fetch-cuda-redist.py 12.8.1 linux-x86_64 /opt/cuda
"""

import hashlib
import json
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

BASE_URL = "https://developer.download.nvidia.com/compute/cuda/redist"

# nvcc ships nvvm/crt in 12.x; nvrtc and the profiler API are pulled in by
# CMake's FindCUDAToolkit / ggml-cuda's headers.
COMPONENTS = [
    "cuda_cudart",
    "cuda_nvcc",
    "cuda_nvrtc",
    "cuda_cccl",
    "cuda_nvtx",
    "cuda_profiler_api",
    "libcublas",
]


def _download(url: str, target: Path) -> None:
    with urllib.request.urlopen(url) as resp, target.open("wb") as out:
        shutil.copyfileobj(resp, out)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _extract(archive: Path, into: Path) -> Path:
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(into)
    else:
        with tarfile.open(archive) as tf:
            tf.extractall(into, filter="tar")
    roots = [p for p in into.iterdir() if p.is_dir()]
    if len(roots) != 1:
        raise SystemExit(f"unexpected layout in {archive.name}: {roots}")
    return roots[0]


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    version, platform, dest = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    dest.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp_name:
        tmp = Path(tmp_name)
        manifest_path = tmp / "redistrib.json"
        _download(f"{BASE_URL}/redistrib_{version}.json", manifest_path)
        manifest = json.loads(manifest_path.read_text())

        for component in COMPONENTS:
            entry = manifest[component][platform]
            archive = tmp / Path(entry["relative_path"]).name
            print(f"{component} {manifest[component]['version']}", flush=True)
            _download(f"{BASE_URL}/{entry['relative_path']}", archive)
            actual = _sha256(archive)
            if actual != entry["sha256"]:
                raise SystemExit(
                    f"SHA-256 mismatch for {archive.name}: "
                    f"expected {entry['sha256']}, got {actual}"
                )
            unpack_dir = tmp / f"x-{component}"
            unpack_dir.mkdir()
            root = _extract(archive, unpack_dir)
            shutil.copytree(root, dest, symlinks=True, dirs_exist_ok=True)
            shutil.rmtree(unpack_dir)
            archive.unlink()

    if platform.startswith("linux"):
        # nvcc.profile links against $(TOP)/targets/<arch>-linux/lib, which a
        # regular toolkit install provides but the merged redist archives do not.
        target = dest / "targets" / f"{platform.split('-', 1)[1]}-linux"
        target.mkdir(parents=True, exist_ok=True)
        for name in ("include", "lib"):
            link = target / name
            if not link.exists():
                link.symlink_to(Path("..") / ".." / name)

    print(f"CUDA {version} ({platform}) installed to {dest}")


if __name__ == "__main__":
    main()
