#!/usr/bin/env python3
"""Download integrity and bounded recovery without external network access."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("decoder", Path(__file__).resolve().parents[2] / "scripts/build-video-decoder.py")
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)


class SourceDownload(unittest.TestCase):
    def test_transfer_failure_integrity_and_retry(self):
        data = b"verified source"
        checksum = hashlib.sha256(data).hexdigest()
        for case in ("success", "retry", "stalled", "corrupt", "budget"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "source.tar.xz"
                responses = {
                    "success": [io.BytesIO(data)],
                    "retry": [TimeoutError(), io.BytesIO(data)],
                    "stalled": [TimeoutError(), TimeoutError(), TimeoutError()],
                    "corrupt": [io.BytesIO(b"wrong")],
                    "budget": [],
                }[case]
                clock = [0, 181] if case == "budget" else None
                with patch.object(decoder.urllib.request, "urlopen", side_effect=responses) as request, patch.object(decoder.time, "monotonic", side_effect=clock, return_value=0):
                    if case in ("success", "retry"):
                        decoder.download_archive("https://example.invalid/source", target, checksum)
                        self.assertEqual(target.read_bytes(), data)
                    else:
                        with self.assertRaises((TimeoutError, ValueError)):
                            decoder.download_archive("https://example.invalid/source", target, checksum)
                        self.assertFalse(target.exists())
                    self.assertEqual(request.call_count, {"success": 1, "retry": 2, "stalled": 3, "corrupt": 1, "budget": 0}[case])
                    for call in request.call_args_list:
                        self.assertLessEqual(call.kwargs["timeout"], 15)
                self.assertFalse(target.with_suffix(".part").exists())


if __name__ == "__main__":
    unittest.main()
