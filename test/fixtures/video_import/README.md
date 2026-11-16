# Video import fixtures

Tiny 0.2-second clips made from this repository's own
`website/public/motion/privacy-local.mov` (ProRes) and `.webm` (VP9), plus the
synthetic tones in `test/fixtures/audio_import/`. No speech or personal data.
The fixtures are covered by the repository's MIT licence.

Generated locally with FFmpeg 8.1.2 (test-fixture tool only; the app builds the
version pinned in `scripts/build-video-decoder.py`). For each container:

```sh
ffmpeg -i <video> -i <audio> -map 0:v:0 -map 1:a:0 -c copy -t 0.2 tone.<ext>
ffmpeg -i tone.mp4 -map 0:v:0 -c copy silent.mp4
```

- `tone.mp4`: VP9 + AAC from `tone_stereo_44k.m4a`.
- `tone.mov`: ProRes + the same AAC source.
- `tone.mkv`: VP9 + the same AAC source.
- `tone.webm`: VP9 + Opus from `tone1s_stereo44.opus`.
- `silent.mp4`: video only, no audio track.
- `corrupt.mp4`: an ISO-BMFF `ftypisom` header followed by invalid data.

The app's helper contains no video decoder: these exercise demuxing a real
video while decoding only its audio. The native test checks nonempty PCM,
plausible duration, no-audio/corruption failures and absence of network/video
decoder support. Dart tests cover sniffing, common picker/drop intake,
process cancellation, partial-output rejection, limits, I/O failures and
queue retry/cleanup separately.
