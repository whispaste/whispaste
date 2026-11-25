#!/usr/bin/env python3
"""Exercise the real bundled helper against tiny, redistributable video fixtures
and the Opus/WebM upload copy of cloud transcription (ADR 0040).

Usage: python3 test/scripts/video_audio_decode_test.py <path-to-ffmpeg>
"""
import array
import math
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

    def test_upload_copy_is_small_opus_webm_that_decodes_back(self):
        # 60 s of a 16 kHz tone with pauses, as the app pipes it (raw samples).
        rate = 16000
        samples = array.array("h", (
            int(8000 * math.sin(2 * math.pi * 220 * i / rate)) if (i // rate) % 4 else 0
            for i in range(60 * rate)))
        # Same arguments as lib/services/audio/upload_audio_encoder.dart.
        encoded = subprocess.run([
            DECODER, "-nostdin", "-hide_banner", "-nostats", "-loglevel", "error",
            "-protocol_whitelist", "pipe",
            "-f", "s16le", "-ar", "16000", "-ch_layout", "mono", "-i", "pipe:0",
            "-map", "0:a:0", "-map_metadata", "-1", "-threads", "1",
            "-c:a", "libopus", "-b:a", "32000", "-vbr", "on",
            "-application", "voip", "-compression_level", "5",
            "-f", "webm", "pipe:1",
        ], input=samples.tobytes(), capture_output=True, timeout=60)
        self.assertEqual(encoded.returncode, 0, encoded.stderr.decode(errors="replace"))
        webm = encoded.stdout
        self.assertEqual(webm[:4], b"\x1a\x45\xdf\xa3")
        # About 32 kbit/s: far below the 1.92 MB WAV, at most a quarter of it.
        self.assertLess(len(webm), len(samples) * 2 // 4)
        self.assertGreater(len(webm), 60 * 32000 // 8 // 4)
        decoded = subprocess.run([
            DECODER, "-nostdin", "-hide_banner", "-protocol_whitelist", "pipe",
            "-f", "matroska", "-i", "pipe:0", "-ac", "1", "-ar", "16000",
            "-c:a", "pcm_s16le", "-f", "s16le", "pipe:1",
        ], input=webm, capture_output=True, timeout=60)
        self.assertEqual(decoded.returncode, 0, decoded.stderr.decode(errors="replace"))
        pcm = array.array("h", decoded.stdout)
        self.assertAlmostEqual(len(pcm), len(samples), delta=rate // 10)
        self.assertGreater(max(map(abs, pcm)), 4000)

    def test_upload_encoder_reads_no_files(self):
        result = subprocess.run([
            DECODER, "-nostdin", "-hide_banner", "-protocol_whitelist", "pipe",
            "-f", "s16le", "-ar", "16000", "-ch_layout", "mono",
            "-i", str(FIXTURES / "tone.mp4"),
            "-c:a", "libopus", "-f", "webm", "pipe:1",
        ], capture_output=True, timeout=20)
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
