---
title: WhisPaste — Microsoft Store long description
version: 1
locale: en-US
last-reviewed: 2026-05-21
notes: |
  Outcome-first marketing copy for the Microsoft Store Partner Center
  "Description" field. Keep in sync with `store/en-US/description.txt` and the
  hero/FAQ copy on whispaste.de, but written as a self-contained marketing
  piece — not a copy of the website. Glossary-konform per CONTEXT.md §7 and
  PRD §D — anti-vocabulary scan must stay green.
---

## Tagline

Press a hotkey, speak, and your words land at the cursor in any app — offline by default, open source, no account.

## Long description

WhisPaste turns the moment you would normally start typing into the moment you start talking. You press a global hotkey, say what you would have written, and the transcript appears at the cursor of whatever app you happen to be in — your inbox, a code editor, a support ticket, a chat window, a browser form. There is no separate window to switch to, no copy step, no second clipboard to manage. The voice input flows directly into the place you already had your cursor.

The default mode runs entirely on your computer. WhisPaste ships three on-device Whisper AI models (Small, Medium, and Large v3 Turbo) so your audio never leaves the machine you are working on. If you ever want cloud-grade accuracy, OpenAI and Deepgram are opt-in and the audio goes straight from your device to the provider you picked — never through a WhisPaste server. There is no account to create, no subscription to manage, and nothing about your work gets stored anywhere it would not otherwise live.

Writers, developers, support staff, and anyone whose hands hurt at the end of the day all use WhisPaste for the same reason: the keyboard becomes optional. A five-sentence reply to a code review takes about ten seconds of voice input instead of two minutes of typing. A first draft of a long email is a single hotkey press away. A clarification on a customer ticket goes out without leaving the ticket UI. On a day when typing is painful, voice input takes over for whichever sentences need to happen, and you keep working without switching tools.

Every transcript is saved to a local history you control. Search across everything you have ever recorded, tag entries by project, pin the ones you reuse, archive what you do not need, and export to TXT, Markdown, JSON, CSV, or Word whenever you want a copy outside the app. Voice Snippets turn short spoken triggers into reusable phrases — signatures, greetings, project codes, anything you find yourself typing repeatedly — and they are expanded before the text is pasted.

WhisPaste is open source under the MIT license. The full source is on GitHub, every release is built transparently through GitHub Actions, and the Microsoft Store version adds automatic updates and a way to support the project financially without changing how the app works.

## What you can do with it

- **Reply to email** in your own words without touching the keyboard — Outlook, Gmail, anything in the browser.
- **Answer code reviews, write commit messages, and comment on issues** without leaving the GitHub or GitLab tab.
- **Work through support tickets faster** by speaking the personal sentences on top of your macros, right inside Zendesk, Freshdesk, Intercom, or your own helpdesk app.
- **Keep writing on bad-hands days** if you live with RSI, carpal tunnel, or tendonitis — voice input replaces typing wherever your cursor is.
- **Brainstorm and outline out loud**, then edit the transcript instead of staring at an empty document.
- **Capture meeting notes and follow-ups** straight into Notion, Obsidian, OneNote, or whatever notes app you use.
- **Talk to chatbots and AI tools** by speaking the prompt instead of typing it, then refine the result in place.

## Platforms, license, and privacy

- **Platforms:** Windows 10 (64-bit) and newer, macOS 10.15 Catalina and newer. A Linux version is planned.
- **License:** MIT — open source, source available on GitHub, audit every line.
- **Privacy:** Offline by default. On-device transcription runs without any internet connection; the cloud path is opt-in and audio travels directly from your device to the provider you choose, never through a WhisPaste server. No account is required, and optional crash reports can be turned off at any time.
- **System requirements:** 8 GB of RAM is required and enforced at startup. A dedicated GPU with 2 to 4 GB of VRAM (NVIDIA CUDA, AMD or Intel Vulkan) speeds up transcription by roughly five times, but is not required — CPU fallback is always available.
- **Languages:** 99 spoken languages supported for transcription. The interface is available in English, German, and Hebrew.
