# WhisPaste

> WhisPaste is a free, MIT-licensed voice-input app for Windows, Apple Silicon Macs and Linux: press a hotkey, speak, and the text lands in the active text field. Speech recognition runs locally on your computer.

## What WhisPaste does

- You press a global hotkey in any application, speak, and press it again (or hold it while speaking).
- WhisPaste transcribes the recording on your computer and copies the text to the clipboard. With Auto-Paste switched on, it inserts the text at the cursor of the active application, in almost any app.
- It is meant for people who write a lot at the desktop: emails, messages, documents, notes, prompts and code comments.

## Speech recognition

- Two local engines: Whisper (whisper.cpp, 99 languages, several model sizes) and Parakeet (about 25 European languages, fast even without a GPU).
- After a one-time model download, local recognition works offline.
- A GPU is optional. Acceleration uses Metal on Apple Silicon and Vulkan on Windows and Linux; an optional CUDA pack is available for NVIDIA. Without a GPU, recognition runs on the CPU.
- Optional cloud recognition through OpenAI or Deepgram with your own API key.

## Smart Mode (optional, off by default)

- Cleanup removes filler words and fixes punctuation, Concise shortens the text, Translate converts it into German, English, Spanish, French, Portuguese, Mandarin or Russian.
- Runs locally (macOS and Windows; experimental on Linux) or through OpenAI with your own API key.

## Everyday features

- Local history of transcripts and separate quick notes.
- Snippets: saved text blocks inserted by hotkey or by a spoken trigger word; interactive snippets fill in a template.
- File import: transcribe existing audio files.

## Privacy

- With local recognition, audio stays on your computer and is discarded after transcription unless you turn on audio retention.
- No account is needed.
- Usage statistics and crash reports contain no audio, transcripts or history and can be switched off in Settings → Privacy.
- Cloud features send data only to the provider you chose and only when you use them.

## Platforms and requirements

- Windows 10 or later, macOS 12 Monterey or later on Apple Silicon (Intel Macs are not supported), Linux x64 (AppImage, .deb, tar.gz).
- Recommended: at least 8 GB of RAM and a 64-bit processor.
- Desktop only; there is no iOS or Android version.

## Price and licence

- The complete app is free on GitHub under the MIT License.
- Paid versions in the Microsoft Store and Mac App Store offer the same core features with updates through the store.
- No subscription. Optional cloud providers may charge for their usage.

## Links

- [Website](https://whispaste.de/en/)
- [Download](https://whispaste.de/en/download/)
- [Privacy policy](https://whispaste.de/en/privacy/)
- [Changelog](https://whispaste.de/en/changelog/)
- [Source code on GitHub](https://github.com/whispaste/whispaste)
