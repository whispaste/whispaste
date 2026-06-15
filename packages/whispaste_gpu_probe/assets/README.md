# assets — PLACEHOLDER files

The WAV files in this directory (`reference_short.wav`, `reference_long.wav`)
are **PLACEHOLDER** files generated programmatically by
`tools/gen_reference_wavs.dart`. They contain a simple 440 Hz sine tone and
carry **no linguistic content**.

**A human must replace these files with real curated German audio + true
soll-transcripts** (`reference_short.txt`, `reference_long.txt`) before any
meaningful live probe run. The transcripts are currently also PLACEHOLDER text.

## Required format

| Property     | Value              |
|--------------|--------------------|
| Format       | RIFF/WAVE PCM      |
| Sample rate  | 16 000 Hz          |
| Channels     | 1 (mono)           |
| Bit depth    | 16-bit signed LE   |

## Target durations

| File                  | Duration  | Notes                           |
|-----------------------|-----------|---------------------------------|
| `reference_short.wav` | ~5–8 s    | Measures startup overhead       |
| `reference_long.wav`  | ~60–90 s  | Measures sustained throughput   |
