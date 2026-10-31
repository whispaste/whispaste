---
title: "New in WhisPaste 1.4: Speak, clean up, rewrite by voice"
description: "Speak emails with real paragraph breaks, drop the “uh” automatically and shorten selected sentences by voice: what WhisPaste 1.4 adds to your writing."
date: 2026-10-17
cover:
  src: "/blog/neu-in-whispaste-1-4/cover.webp"
  alt: "Abstract illustration: a text card with lines of text, one long line highlighted in cyan and a shorter amber line below it with a text cursor"
  og: "/blog/neu-in-whispaste-1-4/og.png"
---

WhisPaste 1.4 lets you speak an email with paragraphs, remove filler sounds and shorten a long sentence by voice. It’s Thursday morning, and a client is waiting for a project update. You know what you want to say and would like to speak it straight into your email.

On macOS, Windows and Linux, WhisPaste uses Auto-Paste to put spoken words into the active text field. Speech recognition runs locally with Whisper by default, with no cloud required. Version 1.4 adds ways to shape that text as you write and revise.

## Speak your paragraph breaks

Place the cursor in your email, press your hotkey and say: “Good morning, the drafts are ready for review. New paragraph. Next, we’ll discuss the remaining questions.” Press the hotkey again to stop recording. With Auto-Paste enabled, the text appears in your email with a real paragraph break.

Spoken line breaks are new: “new paragraph” and “new line” become breaks instead of words in the text. **Spoken line breaks** is on by default. You can turn it off under Settings → Speech Recognition.

The commands exist in all six interface languages, for example “nuevo párrafo” in Spanish, and follow the language you speak in. For the basic Auto-Paste workflow, see [From hotkey to text](/en/blog/vom-hotkey-zum-text-im-aktiven-fenster/).

## Drop the “uh” from your draft

You may still be thinking through the next step as you speak. That doesn’t mean an “uh” or “um” needs to appear in your update. Enable the new **Remove filler words** switch under Settings → Speech Recognition. It is off by default.

<figure><img src="/blog/neu-in-whispaste-1-4/einstellungen-en.webp" alt="Dark WhisPaste settings showing the Remove filler words and Spoken line breaks rows, both switches turned on" width="1750" height="325" loading="lazy" /><figcaption>Both controls are under Settings → Speech Recognition. Both switches are on here; Remove filler words is off out of the box.</figcaption></figure>

WhisPaste removes clear hesitation sounds such as “uh”, “um” and “erm” before saving or pasting the cleaned text. Words with meaning stay intact: German “um” (as in “um 8 Uhr”) stays, and English “um” is only removed when you transcribe in English. History retains the original transcript. Give the pasted email a quick read before sending it.

## Shorten a sentence by voice

As you read, one sentence feels overloaded. The new “Edit-selection hotkey” lets you revise it within your email. First, enable **Edit-selection hotkey** under Settings → Smart Mode. It is off by default.

<figure><img src="/blog/neu-in-whispaste-1-4/bearbeiten-en.webp" alt="Dark WhisPaste settings showing Edit-selection hotkey turned off, its description, and Shift + Cmd + &gt; beside a Change button" width="1750" height="325" loading="lazy" /><figcaption>Enable Edit-selection hotkey under Settings → Smart Mode. Use Change beside the displayed combination to choose another shortcut.</figcaption></figure>

Select the sentence, press the combination shown under “Combination” and say “shorter”. The result replaces your selection. If it isn’t what you wanted, use Undo in your email app to restore the original. Your clipboard is restored too, and the edit doesn’t appear in History.

Alongside “shorter”, the quick commands include “improve” and “translate”, available in all six interface languages. Any other sentence becomes a free-form instruction, such as “Make this a friendly request”. Editing uses Smart Mode, either locally or through the cloud. Local use requires the appropriate Smart Mode model to be downloaded.

## Keep longer thoughts together

After the email, you might want to talk through the rest of the project. The “Max Recording Duration” setting (Settings → Recording Safety) now goes up to 60 minutes, with “Unlimited” at the far right. A desktop shortcut running `whispaste --toggle` starts or stops recording in the running app, useful on Wayland, with a launcher or a Stream Deck.

The interface now includes Spanish and Brazilian Portuguese alongside German, English, Russian and Hebrew, bringing the total to six. The new translations have not yet been checked by native speakers.

WhisPaste no longer crashes on older processors or with older NVIDIA cards. NVIDIA RTX and GTX 16 users on Windows and Linux can optionally download a separate CUDA pack under Settings → Speech Recognition → Graphics acceleration, except in the Microsoft Store version. Without the appropriate CUDA driver, WhisPaste stays with Vulkan. Smart Mode keeps its model loaded, so repeated rewrites don’t reload it each time.

## Start with a short email

For more ideas, see [voice input for everyday writing](/en/use-cases/everyday/). Your next email is enough to get started: speak the paragraph breaks, optionally remove filler sounds and select a sentence to shorten.

If you’re still on 1.3, get the released version 1.4.2 from the [Download](/en/download/) page. It includes the additions from 1.4.0 and the bug fixes in 1.4.1 and 1.4.2. New to WhisPaste? Download the app and try it with a short email.
