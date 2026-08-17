# LibriSpeech sample — provenance and license

20 utterances from LibriSpeech `dev-clean`, speaker 2277, chapter 149896
(`2277-149896-0000.wav` … `2277-149896-0019.wav`), converted from the
original FLAC to 16kHz mono PCM WAV (whisper.cpp's required input format).
Reference transcripts in `2277-149896.trans.txt` are the original
LibriSpeech ground truth for these utterances, unmodified.

- Source: <https://www.openslr.org/12> (`dev-clean.tar.gz`)
- License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- Citation: V. Panayotov, G. Chen, D. Povey and S. Khudanpur, "Librispeech:
  An ASR corpus based on public domain audio books," 2015 IEEE International
  Conference on Acoustics, Speech and Signal Processing (ICASSP), 2015.

Used by `../benchmark-engines-testset.mjs` as the reference test set for the
`/engine-benchmarks/` page's WER numbers. `dev-clean` (not `test-clean`) was
picked for practical reasons — same license and recording quality, smaller
download — and the page/methodology text says `dev-clean` accordingly rather
than implying the canonical `test-clean` split.
