# WhisPaste

> WhisPaste is a free, MIT-licensed voice-input app for Windows, Apple Silicon Macs and Linux: press a hotkey, speak, and the text lands in the active text field. Speech recognition runs locally on your computer.

## What WhisPaste does

- You hold a global hotkey in any application while you speak and let go to stop, or tap it once to start and again to stop.
- WhisPaste transcribes the recording on your computer and copies the text to the clipboard. With Auto-Paste switched on, it inserts the text at the cursor of the active application, in almost any app.
- It is meant for people who write a lot at the desktop: emails, messages, documents, notes, prompts and code comments.

## Speech recognition

- Two local engines: Whisper (whisper.cpp, 99 languages, several model sizes) and Parakeet (about 25 European languages, fast even without a GPU).
- After a one-time model download, local recognition works offline.
- A GPU is optional. Acceleration uses Metal on Apple Silicon and Vulkan on Windows and Linux; an optional CUDA pack is available for NVIDIA. Without a GPU, recognition runs on the CPU.
- Optional cloud recognition through OpenAI or Deepgram with your own API key.
- On Macs with macOS 26 or later, Apple’s on-device speech recognition is a third option.

## Smart Mode (optional, off by default)

- Cleanup removes filler words and fixes punctuation, Concise shortens the text, Translate converts it into German, English, Spanish, French, Portuguese, Mandarin or Russian.
- Runs locally (macOS and Windows; experimental on Linux) or through OpenAI with your own API key.
- Your own presets with your own instruction (up to 500 characters); apply a preset later to an earlier recording, the original is kept. Instead of OpenAI, a compatible server of your own (for example LM Studio or Ollama) on your computer or network works too.

## Everyday features

- Local Recordings area with search, filters, automatic saving and version history, plus notes with titles, images, checklists, a reading view and a focus mode.
- Snippets: saved text blocks inserted by hotkey or by a spoken trigger word; interactive snippets fill in a template.
- File import: transcribe audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) and video files (MP4, MOV, MKV, WebM), up to 1 GB and 6 hours. Audio files can also be sent straight from the file manager: “Open With” on a Mac, on Linux and in the Microsoft Store version for Windows, right-click with the Windows installer from the website.
- Optionally, WhisPaste pauses music and video on Windows and Linux while you dictate, and “Send after pasting” presses Enter after the text is pasted (hold Alt as you release the hotkey; on Linux X11 only).
- “Even out volume automatically” (on by default) raises quiet speech before recognition without amplifying silence or noise.
- Up to five favorite recognition languages, marked with a star, come first in the language menus; a shortcut switches between them.
- The Dictionary holds names and specialist terms; replacements fix recurring spellings, and WhisPaste suggests new ones from your repeated corrections.
- Profiles set language, speech model, Smart Mode, microphone and output for a specific app.
- If a transcription fails, the audio is kept for 24 hours by default, even after a crash, so you can try again.
- Accessibility: settings, notes and editor tools work by keyboard and screen reader; tap mode means you never have to hold a key.

## Privacy

- With local recognition, audio stays on your computer and is discarded after transcription unless you turn on audio retention.
- On macOS and Windows, WhisPaste does not auto-paste into password fields; the text stays on the clipboard.
- Transcripts, notes, the Dictionary, snippets and kept audio are stored encrypted with a data key in the system key store (macOS keychain, Windows data protection, Linux Secret Service). You can back up the key as a recovery code or file.
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
