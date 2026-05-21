---
title: WhisPaste — DMG distribution wording
version: 1
locale: en-US
last-reviewed: 2026-05-21
notes: |
  Texts that appear inside the macOS DMG volume (volume name, welcome card,
  install hint, privacy note) and in the README that ships next to the .app
  bundle. Glossar-konform per CONTEXT.md §7. Keep in sync with the on-site
  tone and the Microsoft Store listing, but worded for first-launch context.
---

## DMG volume name

WhisPaste — voice-input tool

## Welcome card (shown when the DMG is opened)

**Welcome to WhisPaste.** Press a hotkey, speak, and your words appear at the cursor in any app. Offline by default, open source, no account required.

To install, drag the WhisPaste icon onto the Applications folder on the right. You can then eject this disk image and open WhisPaste from Launchpad or Spotlight.

## Drag-to-Applications hint (short string overlaying the DMG background)

Drag WhisPaste to your Applications folder to install.

## First-launch note (shown next to the .app icon as a README-style file)

# WhisPaste

Press. Speak. Done.

WhisPaste turns your voice into text right where your cursor is, in any app you already use — your inbox, a code editor, a support ticket, a chat window. The on-device transcription runs entirely on your Mac; optional cloud providers are opt-in and audio is sent directly to the provider you choose, never through a WhisPaste server.

## Install

1. Drag the **WhisPaste** icon onto **Applications**.
2. Eject this disk image.
3. Open **WhisPaste** from Launchpad or Spotlight.

The first time you launch the app, macOS Gatekeeper may warn that WhisPaste is from an unidentified developer. WhisPaste is open source but not yet notarized by Apple — right-click the app, choose **Open**, and confirm in the dialog to proceed. After that, future launches behave normally.

## First-run permissions

WhisPaste asks for two macOS permissions on first use:

- **Microphone** — required to capture the audio that is then transcribed.
- **Accessibility** — required so the transcript can be pasted at the cursor in the app you are using. WhisPaste never reads or records the contents of other apps; the permission is only used to send a single paste keystroke after each transcription.

You can revoke either permission at any time in **System Settings → Privacy & Security**. WhisPaste degrades gracefully if you skip Accessibility — the transcript is copied to the clipboard and you paste it yourself with Cmd+V.

## Privacy

- **On-device mode** (default): your audio never leaves your Mac.
- **Cloud mode** (opt-in): audio is sent straight from your device to the provider you selected — never through a WhisPaste server.
- **No account, no tracking.** Optional crash reports are transparent and can be turned off at any time.

## License and source

WhisPaste is open source under the **MIT License**. The full source code and every release build are on GitHub — audit any line, build it yourself, or fork it.

- Website: https://whispaste.de
- Source and releases: https://github.com/whispaste/whispaste
- Documentation, FAQ, and use cases: https://whispaste.de
