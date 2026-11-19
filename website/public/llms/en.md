# WhisPaste

> WhisPaste is a dictation app for Windows, Apple Silicon Macs and Linux: press a hotkey, speak, and the text lands in the text field you are working in. Speech recognition runs locally on your computer, and no account is needed. It is open source under the MIT License and free on GitHub; the Microsoft Store and Mac App Store versions are a one-time purchase with no subscription; buying unlocks nothing.

## What WhisPaste does

- You hold a global hotkey in any application while you speak and let go to stop, or tap it once to start and again to stop.
- WhisPaste transcribes the recording on your computer and copies the text to the clipboard. With Auto-Paste switched on, it inserts the text at the cursor of the active application, in almost any app.
- It is meant for people who write a lot at the desktop: emails, messages, documents, notes, prompts and code comments.

## What WhisPaste adds beyond the basics

Local, no account and free to use is the baseline. On top of that, WhisPaste brings:

- Smart Mode with ready-made modes: clean up, shorten or translate into one of seven languages before the text is pasted. To change selected text, say what should be different.
- Smart Mode runs on a local text model that WhisPaste downloads for you when you ask; there is no extra software to install (experimental on Linux). Alternatively, use your own OpenAI key.
- Recordings, notes and snippets in one editor, with the same toolbar, the same shortcuts and autosave.
- A dictionary with replacements that suggests new replacements from your corrections.
- History, notes, dictionary, snippets and kept recordings are stored encrypted with your device's own data key.
- Available in the Microsoft Store and the Mac App Store: on Windows it installs without the SmartScreen warning and updates in the background through the store; on the Mac, installation and updates go through the App Store. One-time purchase, no subscription; the purchase funds development.

## Speech recognition

- Two local engines: Whisper (whisper.cpp, 99 languages, several model sizes) and Parakeet (about 25 European languages, fast even without a GPU).
- After a one-time model download, local recognition works offline.
- A GPU is optional. Acceleration uses Metal on Apple Silicon and Vulkan on Windows and Linux; an optional CUDA pack is available for NVIDIA. Without a GPU, recognition runs on the CPU.
- Optional cloud recognition through OpenAI or Deepgram with your own API key.
- On Macs with macOS 26 or later, Apple’s on-device speech recognition is a third option.

## Smart Mode (optional, off by default)

- Cleanup removes filler words and fixes punctuation, Concise shortens the text, Translate converts it into German, English, Spanish, French, Portuguese, Mandarin or Russian.
- Runs locally (macOS and Windows; experimental on Linux) or through OpenAI with your own API key.
- Your own presets with your own instruction (up to 500 characters); apply a preset later to an earlier recording, the original is kept. Instead of OpenAI, a compatible server of your own (for example Ollama, LM Studio, llama.cpp or KoboldCpp) on your computer or network works too.

## Everyday features

- Local Recordings area with search, filters, automatic saving and version history, plus notes with titles, images, checklists, a reading view and a focus mode.
- Snippets: saved text blocks inserted by hotkey or by a spoken trigger word; interactive snippets fill in a template.
- File import: transcribe audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) and video files (MP4, MOV, MKV, WebM), up to 1 GB and 6 hours. Audio files can also be sent straight from the file manager: “Open With” on a Mac, on Linux and in the Microsoft Store version for Windows, right-click with the Windows installer from the website.
- Optionally, WhisPaste pauses music and video on Windows and Linux while you dictate, and “Send after pasting” presses Enter after the text is pasted (hold Alt as you release the hotkey; on Linux X11 only).
- “Even out volume automatically” (on by default) raises quiet speech before recognition without amplifying silence or noise.
- Up to five favorite recognition languages, marked with a star, come first in the language menus; a shortcut switches between them.
- The Dictionary holds names and specialist terms; replacements fix recurring spellings, and WhisPaste suggests new ones from your repeated corrections.
- Profiles set language, speech model, Smart Mode, microphone and output for a specific app.
- Edit selection (optional, off by default): select text in a supported app, press its hotkey and say what to change, for example “shorter” or “translate”; Smart Mode rewrites the selection.
- If a transcription fails, the audio is kept for 24 hours by default, even after a crash, so you can try again.
- Accessibility: settings, notes and editor tools work by keyboard and screen reader; tap mode means you never have to hold a key.

## Privacy

- With local recognition, audio stays on your computer and is discarded after transcription unless you turn on audio retention.
- On Windows and in the macOS version from GitHub, WhisPaste does not auto-paste into password fields; the text stays on the clipboard.
- Transcripts, notes, the Dictionary, snippets and kept audio are stored encrypted with a data key in the system key store (macOS keychain, Windows data protection, Linux Secret Service). You can back up the key as a recovery code or file.
- No account is needed.
- Anonymous usage statistics and crash reports are on by default. They contain no audio, transcripts or history, and each can be switched off in Settings → Privacy.
- Cloud features send data only to the provider you chose and only when you use them.

## Platforms and requirements

- Windows 10 or later, macOS 13 Ventura or later on Apple Silicon (Intel Macs are not supported), Linux x64 (AppImage, .deb, tar.gz) on Ubuntu 26.04 or newer with glibc 2.43; older Linux systems stay on version 1.4.2.
- Linux runs on X11 and Wayland. Under Wayland the desktop binds the global hotkey (through the shortcut portal on GNOME and KDE, or a custom shortcut that runs `whispaste --toggle`), and a few extras such as single-key hotkeys, double tap and “Send after pasting” need X11. Auto-paste on Linux needs a one-time permission (uinput keyboard or desktop portal); without it the text waits on the clipboard.
- Recommended: at least 8 GB of RAM and a 64-bit processor.
- Desktop only; there is no iOS or Android version.

## How to get WhisPaste and what it costs

- Free on GitHub, the complete app under the MIT License: Windows installer (WhisPaste-Setup.exe) or portable ZIP, macOS DMG, Linux AppImage, .deb and tar.gz. Package managers: winget (`SilvioLindstedt.WhisPaste`) and Scoop on Windows, Homebrew on macOS. You can also build it yourself from the source code.
- Microsoft Store (Windows) and Mac App Store (macOS): a one-time purchase, no subscription. The store shows the current price.
- What the store version adds: on Windows, installation without the SmartScreen warning that the unsigned installer from GitHub can trigger, and automatic updates through the Microsoft Store. On macOS, installation and updates through the App Store. The purchase funds further development.
- Buying unlocks nothing; the free version stays complete, with nothing locked or time-limited. The GitHub builds for Windows and macOS look for new versions and install an update only after you confirm; on Linux, WhisPaste only tells you about a new release and links to it, and you install it by hand.
- Where the versions differ: the optional CUDA pack for recent NVIDIA cards is only available in the GitHub builds (Windows and Linux), not in the Microsoft Store version; GPU acceleration through Vulkan works in both. The Mac App Store version runs in Apple’s app sandbox, so it cannot learn from corrections you make in other apps, does not detect password fields, has no AppleScript fallback for pasting and no tool to repair macOS permissions; the version from GitHub has all of these. The Mac App Store currently ships an older version, so audio and video file import reaches it with the next store update.
- A new version can reach the Mac App Store later than GitHub, because Apple reviews every update.
- No subscription and no account. If you choose a cloud provider (OpenAI or Deepgram), it bills you directly for its usage under your own API key.

## How WhisPaste differs from built-in dictation

- Voice typing built into Windows (Win+H) uses Microsoft’s online speech recognition and needs an internet connection. WhisPaste recognises speech on your computer and works offline after a one-time model download.
- Dictation built into macOS uses Apple’s speech recognition only. WhisPaste lets you choose Whisper, Parakeet, Apple’s on-device recognition (macOS 26 or later) or a cloud provider with your own key.
- Many Linux desktops ship no dictation at all. WhisPaste brings its dictation to Linux as well, with the Wayland limits listed above.
- Built-in dictation types while you speak. WhisPaste inserts the finished text when you stop, keeps it in the searchable Recordings area, applies your Dictionary and Snippets, can clean it up with Smart Mode, and also transcribes audio and video files.

## Links

- [Website](https://whispaste.de/en/)
- [Download](https://whispaste.de/en/download/)
- [Privacy policy](https://whispaste.de/en/privacy/)
- [Changelog](https://whispaste.de/en/changelog/)
- [Source code on GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Latest release on GitHub](https://github.com/whispaste/whispaste/releases/latest)
