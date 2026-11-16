#!/usr/bin/env python3
"""Exercise the real bundled helper against tiny, redistributable video fixtures.

Usage: python3 test/scripts/video_audio_decode_test.py <path-to-ffmpeg>
"""
import array
from pathlib import Path
import subprocess
import sys
import unittest

DECODER = str(Path(sys.argv.pop(1)).resolve())
FIXTURES = Path(__file__).resolve().parents[1] / "fixtures/video_import"


def extract(name, demuxer):
    return subprocess.run([
        DECODER, "-nostdin", "-hide_banner", "-nostats", "-xerror",
        "-protocol_whitelist", "file,pipe", "-f", demuxer,
        "-err_detect", "explode", "-i", str(FIXTURES / name),
        "-map", "0:a:0", "-vn", "-sn", "-dn", "-threads", "1",
        "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
        "-f", "s16le", "-progress", "pipe:2", "pipe:1",
    ], capture_output=True, timeout=20)


class VideoDecodeTest(unittest.TestCase):
    def test_video_formats_produce_audio_without_video_decoder(self):
        for extension in ["mp4", "mov", "mkv", "webm"]:
            with self.subTest(extension=extension):
                result = extract(f"tone.{extension}", "mov" if extension in ["mp4", "mov"] else "matroska")
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                self.assertIn(b"out_time_us=", result.stderr)
                pcm = array.array("h", result.stdout)
                self.assertGreater(len(pcm), 1600)
                self.assertLess(len(pcm), 5000)
                self.assertGreater(max(map(abs, pcm)), 100)

    def test_no_audio_is_an_error(self):
        result = extract("silent.mp4", "mov")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"matches no streams", result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_corrupt_input_is_an_error(self):
        result = extract("corrupt.mp4", "mov")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_build_has_no_network_or_video_decoders(self):
        protocols = subprocess.check_output([DECODER, "-hide_banner", "-protocols"], text=True)
        self.assertNotIn("http", protocols)
        codecs = subprocess.check_output([DECODER, "-hide_banner", "-decoders"], text=True)
        # Actual video decoder rows start with V; the legend starts with V.
        rows = [line for line in codecs.splitlines() if line.startswith(" V") and "=" not in line]
        self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main()
