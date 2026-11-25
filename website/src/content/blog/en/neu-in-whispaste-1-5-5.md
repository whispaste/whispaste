---
title: "New in WhisPaste 1.5.5: every model in one place, languages at a keypress"
description: "A page for every speech and text model with Hugging Face search, a key for each language, names from your contacts in the Dictionary and more for notes: what WhisPaste 1.5.5 brings."
date: 2026-11-25
cover:
  src: "/blog/neu-in-whispaste-1-5-5/cover-en.webp"
  alt: "WhisPaste main window on the Models settings page: Whisper large-v3-turbo active, Whisper small installed, Whisper medium and Parakeet with the note “Not for Japanese”, and the text model Gemma 4 E2B below"
  og: "/blog/neu-in-whispaste-1-5-5/og-en.png"
---

WhisPaste 1.5.5 is out, with two big changes. Every speech and text model now sits on one page, where you compare them, install them and search Hugging Face too. And if you dictate in more than one language, you now switch with a single key instead of relying on automatic detection. On top of that, the Dictionary can take names from your contacts, and notes get a few new tricks.

## All models in one place

The new Settings → Models page lists every speech and text model with its size, languages, speed and accuracy in plain words, and whether it runs on your computer or in the cloud. The model WhisPaste recommends for your computer comes first. You install, switch and remove models right there; before removing one you see how much space it frees.

<figure class="wp-shot"><img src="/blog/neu-in-whispaste-1-5-5/modelle-en.webp" alt="Models settings page with a search field, plus button and filters, and five models with size and status below; Parakeet shows “Not for Japanese”" width="1600" height="1633" loading="lazy" /><figcaption>The Models page with Japanese as a favorite language: Parakeet moves down with “Not for Japanese”.</figcaption></figure>

The page also knows your languages: your dictation language, your favorites and your system's languages. If a model can't write one of them, it says "Not for …" and moves to the end of the list. The recommendation counts your favorites too, so a Japanese favorite no longer gets Parakeet recommended.

The "+" button searches Hugging Face from inside the app: one search field, filters for languages and size (starting at "Fits this computer"), and a model installs in one go. Only models WhisPaste can actually run are listed, each with its license and a note that we haven't checked it. Under "Own models" you can add a model from an address or a file, and every text model has "Settings for this model" if you want the values its vendor recommends.

## Languages at a keypress

If you dictate in two or three languages, until now you either switched by hand or trusted automatic detection, which can turn a short, ambiguous sentence into a language you never speak. 1.5.5 improves both.

Under Settings → Keyboard shortcuts → "Key per favorite language", "Set key" gives each favorite language its own key combination. One press switches straight to that language, and the recording bar briefly shows which one is active. If you'd rather not switch at all, "More dictation keys" lets you add up to three extra dictation keys. Each one always dictates in its own language, optionally with its own Smart Mode, and otherwise works like the main key. For short sentences that's more reliable than any detection.

<figure class="wp-shot"><img src="/blog/neu-in-whispaste-1-5-5/tastenkuerzel-en.webp" alt="Keyboard shortcuts settings: an extra dictation key for French, and below it “Key per favorite language” with keys for German, English and Spanish" width="1600" height="1933" loading="lazy" /><figcaption>An extra dictation key for French and a key for each of three favorite languages.</figcaption></figure>

If you still use "Automatically detect", WhisPaste now only chooses among your favorite languages once you have two or more. The idea came from our [ideas board](https://app.votepit.com/silvio-und-maik/whispaste) and from [H-Masoumi](https://github.com/H-Masoumi) on GitHub. Parakeet also sticks to your languages now: it used to be able to write a Polish dictation in Cyrillic. If Parakeet writes in a script none of your languages uses, Whisper transcribes the same recording again, as long as a Whisper model is installed.

One limit on Linux with Wayland: the desktop only binds the main dictation key there, so the extra keys may not respond in other apps. The settings tell you so.

## Names from your contacts

Speech recognition knows "Miller", but it may not know "Mühlhäuser" or the name of the company you work for. The Dictionary now has "Add names from contacts…" for that. WhisPaste shows the full names and companies from your address book, you pick the ones you want, and from then on recognition spells them right. Addresses, phone numbers and email addresses are never read.

The names can come from macOS Contacts, the Windows contacts or Outlook, GNOME Contacts or the KDE address book, and on any system from a vCard or CSV export. They stay on your device: local recognition uses them, cloud services never receive them. The Flatpak and Snap versions can't reach the Linux address books, so use a vCard export there.

## Link and file your notes

Type `[[` in a recording, note or snippet and WhisPaste opens "Link to…". Pick an entry, and a link with its name appears in the text. The link follows the entry, not its name, so renaming doesn't break it. Above the text you see what a note links to and what links back to it.

Notes can now go into folders, with one level of subfolders. Nothing changes until you create the first folder. Notes also get an archive, saved views, find and replace, an outline for jumping between headings, and a spell check that uses your operating system's dictionaries (on Linux it needs Enchant with a Hunspell dictionary).

When a recording keeps its audio, "Audio by sentence" lists every sentence with its place in the recording. Click one to hear it. It's a quick way to check whether someone really said "Tuesday".

## Smart Mode on a single paragraph

In recordings and notes, Smart Mode can now work on part of the text. Select a passage and choose "Cleanup", "Concise", "Translate …" or "Own instruction …" from the context menu, or press Ctrl+J (⌘J on the Mac). Without a selection it takes the paragraph at the cursor, never the whole text. A single undo brings the old wording back, and if the model changes numbers or names, WhisPaste replaces nothing.

## Quiet while you dictate

Settings → Recording & audio → "Media while dictating" now offers "Pause" and "Turn down". Music or a video that is playing stops or gets quieter while you dictate, and afterwards returns to exactly the volume it had, even if you cancel the dictation. This one came from the ideas board too. On the Mac, Music and Spotify can be paused; other playback, such as a video in the browser, is turned down on macOS 14.2 or later.

## And a few more things

- The app now also speaks French, Italian and Simplified Chinese. No native speaker has reviewed these translations yet, so corrections are welcome.
- With OpenAI or Deepgram, recordings of 30 seconds or more are sent as compressed Opus audio. A ten-minute part shrinks from about 19 MB to about 2.4 MB.
- The leading space that recognition often puts at the start of a line is removed before inserting.
- Invented lines at the end of a dictation, like "Subtitles by …", are dropped, but only when the recording really was silent there.
- You can import MPEG, VOB and MPEG-TS videos too, for example from a camcorder, a DVD or a TV recording.
- On Windows, "Transcribe with WhisPaste" now appears in the Explorer context menu in the Store version as well, for audio and video.
- From the command line you can start, stop and cancel a dictation or transcribe a file, which helps if you want your own shortcut under Wayland.

## Thanks

[artepdoos](https://github.com/artepdoos) reported on GitHub that saved OpenAI and Deepgram API keys were no longer loaded after a restart. That affected 1.5.0 to 1.5.2 and is fixed; the key itself stayed stored the whole time. [H-Masoumi](https://github.com/H-Masoumi) got the language work started. Thank you both, and everyone who voted on the ideas board.

## Updating to 1.5.5

Get WhisPaste 1.5.5 from the [download page](/en/download/). If you use the Microsoft Store or Mac App Store version, the update arrives there once the store has approved it. After the start, the Overview shows a card with the main changes. If you dictate in more than one language, your favorite languages are the first thing worth a look.
