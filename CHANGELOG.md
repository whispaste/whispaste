# Changelog

All entries are written in English.

## 1.5.0

### Highlights

- **Your data is stored encrypted:** history, notes, dictionary, snippets, settings and kept recordings are encrypted with your device's own data key. You can back the key up as a recovery code or file and restore it under Settings > Privacy. There is no way back to 1.4.x afterwards (see Known issues).
- **Overview start page:** WhisPaste opens on an Overview with your dictation keys, weekly figures and newest recordings; optional cards add weather, news, recent notes and more.
- **Recordings come out evenly loud by themselves:** quiet speech is raised to a steady level before it is transcribed (on by default).
- **One editor for recordings, notes and snippets:** the same toolbar, shortcuts and autosave everywhere, plus focus mode, a formatted reading view with checklists, text versions and smooth editing of very long notes.
- **Smart Mode with your own presets:** Smart Mode has its own page, and you can create named presets with your own instruction.
- **Up to five favorite languages:** pin them with a star in the language dialog or the dock; the tray and floating button list them first.
- **No automatic paste into password fields on macOS and Windows:** the text stays on the clipboard for you to paste by hand.
- **Undo by keystroke:** after a voice edit, "Undo" reverts the insert in the target app on macOS, Windows and Linux (X11) where that is safe.
- **More ways to dictate:** import video files, pause music while you dictate and send a chat message right after pasting (both opt-in), and on macOS 26+ optionally use Apple's on-device speech recognition.
- **Tray panel:** clicking the tray or menu bar icon opens a compact panel with status, start/stop and your last recordings.
- **Linux: Auto-Paste asks first:** the .deb package no longer grants keyboard access on install; WhisPaste asks for it, and you can withdraw it again in the settings.

All changes are listed below.

### New Features

- **Transcribe audio files from the file manager:** with the Windows installer from the website, right-click a WAV, MP3, FLAC, M4A, AAC, Ogg or Opus file and choose “Transcribe with WhisPaste” (on Windows 11 under “Show more options”; the entry is in German or English). In the Microsoft Store version and on Linux, WhisPaste is listed under “Open With” for these files, on macOS for audio files (a type WhisPaste cannot read gets a short notice). WhisPaste starts, or the open WhisPaste takes the file over, and transcribes it like a file you add in the app. It never becomes the default app for audio files, and uninstalling removes the entry.
- **Recordings come out evenly loud by themselves:** the new setting “Even out volume automatically” (on by default) raises quiet speech to a steady level right after you stop speaking, before it is transcribed. Recognition, the saved recording and playback are equally loud; silence and background noise are not amplified, and loud parts are never turned down or cut off. If you had changed the old “Microphone sensitivity” slider, your value stays and the automatic level stays off until you switch it on. The slider is now called “Input volume” and goes from quieter to louder in decibels; it can no longer mute the microphone, and loud parts are limited gently instead of crackling. The “too loud” hint appears only when a noticeable part of a recording was overdriven. Works the same on macOS, Windows and Linux (#1611).

- **Weather on the Overview:** an optional "Weather" card (off by default, switch it on under "Customise overview") shows the temperature, conditions and the day's low and high for a place you choose. You search the place yourself, nothing is sent while you type and no location services are used; only the place rounded to about one kilometre goes to MET Norway, at most about once an hour and only while the Overview is open. Offline the card stays quiet and keeps the last forecast. Weather data: MET Norway, CC BY 4.0; place search: © OpenStreetMap contributors. Works the same on macOS, Windows and Linux (#1569).
- **News on the Overview:** an optional "News" block shows the newest entries of up to five RSS or Atom feeds you choose, with title, source and date only; a click opens the article in your browser. It is off by default; switch it on under "Customize overview" and pick the feeds under "Sources" (the WhisPaste blog is suggested). Feeds are asked only while the Overview is open, at most once an hour each, and never in the background.
- **See what you dictate with on the overview:** the optional “System” card (switch it on under “Customise overview”) now shows the speech recognition engine, the speech model and the microphone above the load figures. The rows follow your settings at once and say plainly what is missing, for example “not downloaded”, “loads with the next dictation” or “no microphone found”. Nothing is read in the background; the microphone list is refreshed only when the card appears. Works the same on macOS, Windows and Linux (#1567).
- **Select several notes at once:** tick notes with the select button, Ctrl/Cmd+click or Space, a range with Shift+click or Shift+arrow, or all with Ctrl/Cmd+A, as in Recordings. The ticked notes go to the trash after one confirmation, get a tag, become favorites, are exported to one file or merged into a new note (Ctrl+M); in the trash they are restored together. One “Undo” takes the whole action back, and a screen reader announces how many notes are ticked. Works the same on macOS, Windows and Linux (#655).
- **Transfer dictionary terms and undo learning:** import local CSV, text or JSON vocabulary lists from the Terms tab or setup, review new/existing/invalid entries, select terms and confirm. Duplicate terms are merged without overwriting existing spellings; CSV export saves the list locally. Terms accepted from suggestions show “Learned”, and Undo removes the added term and reopens its suggestion. Import limits are one file, 1 MiB, 5000 entries and 60 characters per term (#624).
- **Insert snippets while writing:** in the note, transcript and snippet editors, press Cmd/Ctrl+Shift+I or use the toolbar button to search your snippets and insert one at the cursor. Selected text in a note can be saved as a new snippet, which then links back to its note. The snippet editor now grows with long texts instead of capping the line count.
- **Rebuild index:** Settings > History has a new "Rebuild index" item that rebuilds search and previews from your recordings, newest first, and shows the progress. If WhisPaste finds a missing or damaged search index at start, it rebuilds it by itself and tells you. Your texts are only read, never changed. Works the same on macOS, Windows and Linux (#668).
- **Favorite languages: up to five, set by star in the language dialog:** you can now keep up to five favorite languages instead of three (existing lists stay as they are). You set and remove favorites with the star on each language in the "Recognition language" dialog (Settings > Speech recognition > Change); the separate "Favorites" row below the language is gone, so there is one way to do it. The dialog lists your favorites on top in a group of their own, in the order in which you pinned them; a new favorite goes to the end. The same order is used by the dock language menu, the tray, the floating button menu and the "next favorite language" shortcut. The star switches at once, sits centred on the tile, has a tooltip and a screen-reader name and is reached by Tab. All tiles have the same height, the chosen one has a tick as well as its colour, and the current choice stays visible below the list. Existing favorites and their order are kept. The "No favorite languages yet" notice of the language hotkey now opens this dialog directly. The manual explains how to pin, the limit and where favorites appear. Works the same on macOS, Windows and Linux (#1207, #1210, #1610).
- **Entries open where you left them:** recordings, notes and snippets remember the cursor or selection, scroll position and text size per entry, also across restarts. Focus goes into the text and screen readers announce the paragraph. Ctrl/Cmd + Plus, Minus and 0 change one entry's text size. The state is stored beside the text, never in it, and is deleted with its entry (#678).
- **Reliable undo and redo in every editor:** notes (including very long notes), a recording's transcript and snippets share one undo history with Undo and Redo buttons at the start of the toolbar. Typing, toolbar formatting, Replace and Replace all, dictation and smart actions can all be undone; keys typed within half a second undo together, an IME composition is never split, and at least 1,000 steps are kept. Autosave keeps the history, and switching to another entry parks it until you come back. Same shortcuts on all systems: Cmd+Z / Cmd+Shift+Z on macOS, Ctrl+Z / Ctrl+Shift+Z and Ctrl+Y on Windows and Linux (#651).
- **Focus mode for notes:** Cmd/Ctrl+Shift+Enter, the focus button in the editor toolbar or the editor menu switches the open note to full screen without the sidebar, title bar and note list; the same shortcut or Esc ends it. Toolbar, menu and dock stay available. Optional paragraph focus dims every paragraph except the one you are writing and is remembered (#669).
- **Smart Mode gets its own page and your own presets:** Smart Mode now has its own page in the sidebar; the settings search still finds its options. Create named presets with your own instruction (for example "Write it as a polite e-mail") and pick them as the standard preset. Overlay and dock show the same preset name, and "Compare before and after" on a refined entry in History shows the text before and after Smart Mode.
- **Both buttons of an overlay notice by keyboard:** on a notice with two buttons, one press of the action key (F12, or Escape when F12 cancels) runs the first button and two quick presses run the second. No extra global key is taken. The buttons and the footer name the key way, and it stays visible when a long label is shortened. Works the same on macOS, Windows and Linux (#816).
- **Formatted reading view and checklists:** recordings and notes (new "Reading view" toggle) show Markdown formatted: headings, bold, italic, lists, quotes, code and checklists. Tick tasks with the mouse or keyboard; the state is saved in the text as `- [ ]` / `- [x]`. Below a checklist, "Check all", "Reset" and "Move done to bottom" are available. "Copy" gives plain text with ☐/☑, "Copy as Markdown" keeps the source. Works the same on macOS, Windows and Linux (#643).
- **Check model speed during setup:** on weak or unknown hardware, the model setup view tests a bundled speech clip with the compact model before choosing a suitable model size. The test runs for at most 20 seconds after the preparation download, can be cancelled, and keeps the hardware recommendation if it cannot finish. Strong hardware skips the test (#565).
- **Search and filters in one row on Recordings, Notes and Snippets:** the search, a "Filter" button, the sort and view tools and the "New" button share one row, also at 800 px width, 130 % text and in right-to-left languages. The "Filter" button opens all filters in one panel: on Recordings the view, period and length, on Notes the view and your tags, on Snippets the trash. Each active filter shows as a small mark next to the search; its X removes it, and the number on the button counts them. All filters work as before. Works the same on macOS, Windows and Linux (#1201).
- **Filter recordings by length:** the "Duration" group in the Recordings filter narrows the list to recordings under 1 min, 1–5 min or over 5 min. It works together with the search and the other filters; if nothing matches, the empty list names the active length and offers "Reset filter".
- **Notes page in the same layout as Recordings:** search and the "New note" button on top, with the Notes and Trash view and your tags under "Filter", sort and "Group by date" in the same row. The list keeps its height in small windows, with larger text and in right-to-left languages. Works the same on macOS, Windows and Linux (#1183).
- **One editor for recordings, notes and snippets:** the same bar above the text with undo and redo, formatting and find and replace, the same shortcuts, and below the text the word count with reading time and the save rule: saved as you type, Ctrl+S (Cmd+S on the Mac) saves right away. A recording's text can now be selected and copied while you read it; "Edit transcript" or Ctrl+E (Cmd+E) switches to editing without moving a button
- **Input Monitoring explained before the macOS prompt:** when you choose a single key or a double tap as your trigger in the setup on a Mac, the page first says why WhisPaste needs Input Monitoring and asks only when you press “Allow Input Monitoring”. If the system no longer shows its dialog, System Settings opens with the helper panel. The page notices the grant without a restart and the double tap works right away; with a key combination, or with the grant already given, the step does not appear (#1199).
- **API keys in one place:** Settings has a new area "API keys" with one field each for OpenAI and Deepgram, a show/hide toggle, a status (stored, missing, keyring locked) and which features use the key. Speech recognition and Smart Mode keep the provider choice and only show the key status with a link to that area. Existing keys stay where they are; nothing to migrate, and the export still contains no keys (#208).
- **Reprocess a recording with another mode:** in the recording's detail, choose a mode and run it again. The original transcript is kept; the result is its own version that remembers the mode, you can switch between original and result, and "Undo" in the notice or the detail bar returns to the previous version. Nothing runs without your choice: the local model stays the default, the cloud only with the provider you already set up. Works by keyboard, and progress and result are announced to screen readers. Dictation via the hotkey is unchanged. Works the same on macOS, Windows and Linux (#680).
- **Recent notes on the overview:** a quiet "Notes" section below the latest recordings lists your three most recently edited notes, in the same style. Clicking one opens it in Notes, "All" opens the Notes page, and without notes a single line offers "New note". The section can be hidden under "Customize overview" (#630).
- **Tray panel instead of a plain menu:** clicking the tray or menu bar icon opens a compact panel with the status, a button to start or stop dictating, your last three recordings, quick switches for microphone, language favorites, profile and Smart Mode, plus "Open WhisPaste", "Settings" and a "…" menu that holds rarely used commands and Quit. It works by keyboard (Tab, arrow keys, Enter, Escape), closes on a click outside, keeps the focus in the app you are writing in and falls back to the plain menu if it cannot open. A right click still shows the plain menu; on Linux, where tray icons report no left click, "Open panel" is the first entry of the tray menu. (#920)
- **Automation for notes:** the local API, the command line (`note append|replace|tag|pin`) and the MCP server can now append text to a note, replace text in it, tag it and pin or unpin it. Notes are addressed by their stable ID, and every action is logged like the other automation calls.
- **Accessible editor tools:** the formatting bar and the find bar in Notes, History and snippets work fully by keyboard and screen reader and are easier to hit with an unsteady hand. Every button has a 48 dp target, a spoken name with its shortcut, and a stable test ID. Every paragraph style has a shortcut (Cmd/Ctrl+Shift+H heading, +7 numbered list, +T checklist, +9 quote, +C code; +L bulleted list as before), and a new checklist button joins the bar. Tab goes from the text to the bar as one stop; arrow keys, Home and End move inside it. The same on macOS, Windows and Linux (#652).
- **No automatic paste into password fields on macOS:** WhisPaste now recognises a password or PIN field through the Accessibility permission (only the field type is read, never its content). The text stays on the clipboard and in your history, and you paste it by hand. Without the permission nothing changes.
- **Import video files:** choose or drop MP4, MOV, MKV or WebM files to transcribe their first audio track. Extraction runs locally, shows progress and can be cancelled; the original video is never changed or uploaded. Videos without sound and damaged files get an explicit error, with retry available. The existing 1 GB and six-hour import limits apply.
- **Pin languages straight from the dock:** every language in the dock's language menu has a star to pin or unpin it, by mouse or keyboard, without leaving the menu. Pinned languages sit right below "Detect automatically", the active language is in view when the menu opens, and at the limit the menu says how many favorites are allowed (#1208).
- **F13–F24 as dictation keys:** record a free function key without modifiers, save it and use it again after restarting. Windows supports F13–F24; macOS exposes native codes up to F20. The Linux fork maps F13–F24 and handles X11's default F13 → XF86Tools assignment. Hold and double-tap use the existing dictation gesture path; Wayland needs a desktop portal binding and release events. The recorder and manual explain the setup in all app languages. Windows F13 capture and native press/release events were checked in the app; Linux X11/Wayland and macOS device acceptance remain pending (#354).
- **Favorite languages first in the tray and the floating button:** the Language submenu in the tray and in the floating button's menu lists your favorites in their order, with a check mark on the active language. "More languages…" at the end opens Settings with the full language selection. Works the same on macOS, Windows and Linux (#1209).
- **Old keychain entries move once, announced (macOS):** if secrets from earlier versions still sit in the login keychain, WhisPaste says so first and moves them with one confirmation, so a system dialog for every entry is gone for good. The old entries are removed only after the copy is verified. If you decline or cancel, the app keeps running, the affected feature says what is missing, and Settings > Privacy offers to start it again (#1163).
- **No Markdown markers in mail and chat:** snippets are pasted as plain text, so markers such as ** or # no longer land in other apps. The copy button and Cmd/Ctrl+C on a recording or a note also copy plain text; "Copy as Markdown" in the overflow menu keeps the markers, and the new setting "Paste snippets with Markdown" pastes snippets as before. Dictation via the hotkey is unchanged. Works the same on macOS, Windows and Linux (#644).
- **Very long notes stay smooth:** long notes build only nearby sections for scrolling and editing, including texts with 100,000 words. Mouse and keyboard selection, undo/redo, search and dictation at the cursor work across sections; an ongoing IME composition keeps its input connection until it commits. Screen-reader focus brings the next section into view. "Go to paragraph" (editor menu, Cmd/Ctrl+G) jumps to a paragraph number and announces it. There is no length limit; from about one million characters a notice offers "Split note". Highlights are read once per text change instead of on every cursor move, and search waits briefly after your last keystroke and abandons a running scan when you type again. Short notes behave exactly as before. Works the same on macOS, Windows and Linux (#640, #641).
- **Choose how many recordings keep their audio:** with audio retention on, Settings > Privacy offers 5, 10, 20, 50 or 100 recordings. The default stays 20; a lower count applies at the next cleanup, and the independent 30-day limit stays in place. Failed recordings kept for retry never count towards this limit. Works the same on macOS, Windows and Linux (#980).
- **Restore a lost data key:** when the data key is missing, for example after moving your data folder to a new device, Settings > Privacy offers "Restore": type the recovery code, or choose or drop the backup file, and your history and recordings are readable again. A wrong or damaged backup is named clearly and changes nothing. Without a backup, "Create new key" in the same dialog starts over only after a clear warning: data encrypted with the old key stays unreadable, and its files are kept, not overwritten.
- **Back up your data key:** once the data key exists, Settings > Privacy offers "Back up": show a recovery code to write down or copy, or save a backup file. Both hold the same key, need no password and are as valuable as the key itself, so keep them safe, not next to your data and not unprotected in a cloud. The code has a checksum that catches typos, copying it keeps it out of clipboard history, and the row shows when the key was last backed up. Works the same on macOS, Windows and Linux (#1166).
- **Pause music and video while you dictate (opt-in):** turn on "Pause media while recording" in the recording settings and WhisPaste pauses what is playing as soon as you start dictating, then resumes only what it paused itself. Playback that was already paused stays paused. Where a system does not allow it, the setting says "not available".
- **Recordings are stored encrypted:** recordings kept on your device are now encrypted with your device's own data key and can only be played or transcribed again by WhisPaste on this device. Recordings from before the update are encrypted once in the background shortly after start; if the app is closed meanwhile, it continues at the next start, and a recording is never lost on an error. Audio waiting for a retry and audio of an imported file are encrypted as well. Dictating feels the same. Works the same on macOS, Windows and Linux (#1021).
- **History, dictionary and snippets are stored encrypted:** the local database with your transcripts, notes, dictionary, snippets and settings is now encrypted with your device's own data key. An existing database is converted once at start, after a verified backup; if anything goes wrong, the previous database stays as it was and the next start tries again. Dictating feels the same. Works the same on macOS, Windows and Linux (#1020).
- **Notes without a mouse:** the down arrow in the search field moves into the list, Enter opens the note with the cursor in its text, Escape goes back to the list with the note still open and a second Escape closes it. Escape in the search field clears it, Ctrl/Cmd+N creates a note from anywhere on the page, and the selected row stays in view.
- **Snippets and replacements fill in system variables:** write `{$date}`, `{$time}`, `{$clipboard}`, `{$title}` or `{$cursor}` in a snippet and it is filled in when you insert it. Date and time follow the system language and take a format after the colon, for example `{$date:yyyy-MM-dd}`. An empty or non-text clipboard gives nothing, and the clipboard is only read on your computer. Replacements understand the variables too (without the clipboard). A variable WhisPaste does not know stays in the text as typed, and the editor warns about it while you type. The fields of interactive snippets (`{{field}}`) work as before. Works the same on macOS, Windows and Linux (#663).
- **Statistics: activity over 16 weeks, instant figures, numbers that stay:** the activity panel now shows the last 16 weeks day by day and your streak in days; one missed day does not break it, and when there is no streak nothing is shown instead of a "streak lost" message. Opening the page shows the last figures at once while the fresh ones load in the background. All figures, including the word counts, now come from the statistics' own counts: deleting recordings or turning off saving no longer changes them, only Reset does. If one figure cannot be loaded, only that panel shows a retry and the others stay visible. Works the same on macOS, Windows and Linux (#887).
- **Apple speech recognition in the first-run setup (macOS 26+):** the speech model step now offers Apple's on-device speech recognition as a third card next to Whisper and Parakeet. It needs no large download because it is part of the system; it works only on the Mac and only for the languages the system supports. The recommended model stays preselected. When you choose Apple, the system downloads the language with progress and "Next" waits until it is ready; the test recording then uses Apple speech recognition. Windows, Linux and older macOS versions look as before.
- **The support ask is now a quiet card:** instead of a dialog, a card on the Overview asks for support, never while you dictate, never on the same day as the milestone or rating card and never while the status line reports a problem. "Support" opens Help › Support, "Later" waits 90 days, "Don't ask again" ends the ask for good. It shows at most three times, only after 40 pasted dictations on at least five days, and never once you support WhisPaste or a store payment is pending (#1094).
- **Dictionary shows where each replacement came from:** every replacement now carries a marker: "Manual" for ones you added, "Learned" for ones from your corrections, "Imported" for ones from a file. Starred replacements come first in every sort order, as in snippets and notes. When you save, the replacement dialog checks the same rules as the rest of the dictionary: at most 60 characters per trigger, no trigger twice, and no trigger equal to its replacement. Works the same on macOS, Windows and Linux (#892).
- **Live transcript with Apple speech recognition (macOS 26+):** with the on-device engine set to Apple speech recognition and a fixed dictation language, the overlay now shows your words while you speak, as it already did with Whisper. The preview never replaces the final text, which still comes from the finished recording. Small overlay sizes without text start no preview; it is not available with Parakeet (#1078).
- **Recordings and Notes keep your place:** when you switch to another page and come back, Recordings still shows your selection, multi-selection, view, sort order, scroll position, search and filter; Notes reopens the note you had open at the same scroll position with your search and filter. A fresh app start opens both pages clean (#1074).
- **"Other amount" in the support dialog:** below the fixed amounts, a new entry unfolds GitHub Sponsors, Ko-fi, Buy Me a Coffee and PayPal, so you can give any amount in the way you prefer. Each build shows only the ways it is allowed to offer.
- **Send after pasting (opt-in):** turn on "Send after pasting" in the text settings, then hold Alt (Option on macOS) while you release the dictation shortcut. After the text was pasted successfully, WhisPaste presses Enter, so chat messages go out without reaching for the keyboard. Nothing is sent when pasting fails. Off by default; the settings point out a conflict if Alt is part of your shortcut. On Linux it works on X11, not on Wayland (#564).
- **Contact and feedback form keeps your message:** the form now reaches the team the same way as the contact form on the website. Category and rating are optional. Your draft stays when you leave the page, when sending fails or when you are offline; after an error, "Send again" retries. A reply e-mail address is optional and explained right at the field. Diagnostic data is added only if you choose it, and you can see it before sending. If sending is not possible, the form shows the contact address with "Copy address" (#998).
- **Snippets can be sorted by recent use:** the snippets list has a new sort option "Recently used" and shows, quietly under each snippet, how often and when it was last inserted. The numbers stay on this device and are counted when you insert a snippet from the picker, by name, or copy it on the page. Search ranks title matches before text matches (#865).
- **Onboarding tests your microphone where it asks for it:** the system microphone dialog now appears only on the access page, after you tap "Allow", never earlier. The page then shows a live level so you can see the microphone hears you; "Next" waits until speech is heard, and "Skip" stays available. Choosing another microphone restarts the test, and the test stops when you leave the page. If access was refused, macOS and Windows offer "Open System Settings", Linux points to the sound settings.
- **The tray icon shows the dictation state:** while you dictate, the tray icon carries a red dot; while the text is being transcribed or refined, an amber ring. At rest it looks as before. The tray menu's status line now also names "Processing…", and the tooltip starts with the state during a dictation (Linux has no tray tooltip). Works the same on macOS, Windows and Linux.
- **Microsoft Store: more ways to support WhisPaste:** Help > Support now also offers PayPal, Ko-fi and Buy Me a Coffee after the native tip and GitHub Sponsors. External support unlocks nothing; the coffee button still uses the native Store purchase.
- **Mac App Store: all ways to support WhisPaste:** Help > Support and the support reminder now offer GitHub Sponsors, Ko-fi and PayPal next to the in-app tip, as the direct builds do. Nothing is unlocked by supporting.
- **Quick notes show when each dictation was added:** every dictation the quick-note hotkey appends to a note now carries its moment, without adding an entry to Recordings. The new setting "Dictation time" (Settings › Shortcuts) offers a margin mark beside the dictation's first line with the time as tooltip (the default), a text line with date and time above the dictation, or both. Works the same on macOS, Windows and Linux.
- **Dictionary terms: the line where terms stop working is exact:** the terms list and the speech recognition now count the same text against the recognition's room, so the line "From here on the recognition no longer uses the terms" sits exactly where terms stop reaching it; empty entries and stray spaces no longer use up room unseen. The manual explains that the order of the terms is their priority and how to move an important term up. Works the same on macOS, Windows and Linux.
- **Apple speech recognition on Mac (optional):** on macOS 26 and later, Settings → Speech recognition offers Apple's on-device speech recognition as a third engine next to Whisper and Parakeet. It uses the language chosen in Settings, never the system language. When that language is set to automatic or not supported, the language download is missing, or a run fails or takes too long, the same recording goes to the local engine and a calm notice says so once. Temporary audio lives in a private folder that is cleared at app start. Windows and Linux do not show this option.
- **No auto-paste into password fields on Windows:** when the focused field is a password or PIN field, WhisPaste does not paste or type into it. The text stays on the clipboard and in the history, and a notice (also announced to screen readers) says "Password field detected — please paste by hand". Only the field's type is read, never its content. macOS has the same protection (see "No automatic paste into password fields on macOS"); Linux keeps pasting as before for now.
- **Onboarding says how long your text stays:** the closing privacy page now states how many recordings are kept and after how many days older ones are deleted from the trash (read from your Recordings settings; favorites stay), in all app languages.
- **Compare versions word by word:** in the version list of a recording's text and of a note, the new compare button shows what changed since that version: added words are underlined, removed words struck through, and each is also labelled for screen readers. Only the sections that differ are shown, and "Take over this section" brings one section back from the old version while keeping the replaced text in the list. Long dictations without blank lines (20,000 words) are compared in the background without freezing the window.
- **Versions of a recording's text:** when you edit the text of a recording, earlier states are kept. The clock icon beside "Edit" lists them with time, source (dictated, typed, converted, restored) and length; "Restore" brings one back and keeps the replaced text in the list, so a restore can be undone. Typing within ten minutes counts as one version, and at most 50 are kept per recording, oldest first (the list says so). The original text and the Smart Mode result are unchanged. Works the same on macOS, Windows and Linux.
- **A single-key hotkey that stops listening is noticed on macOS and Windows too:** the key watcher now reports whether it still runs, so a disabled macOS event tap or a dropped Windows key registration is rebuilt automatically instead of leaving the key silently dead. Same on macOS, Windows and Linux.
- **Select several snippets and handle them together:** press Space on the highlighted row, hold Ctrl or Cmd while clicking a row, or choose "Select snippets" in the list menu. A bar shows how many are marked and offers "Select all", moving them to the trash (the "Undo" message names the number), adding or removing the star, and exporting them as TXT, Markdown or JSON. Esc or "Cancel" leaves the selection. Works the same on macOS, Windows and Linux.
- **Hint cards can be silenced or kept:** the short-press card now has a second button "Don't show again" (remembered in the settings), and the wrong-language card has "Keep", which keeps your fixed language and stops asking about that language until the next start. A speech model download started from a card now shows its progress in percent at the pill and says when the model is ready. Works the same on macOS, Windows and Linux.
- **Statistics lead with your words and pace:** the Statistics page now opens with words dictated, words per minute (from speaking time only) and time saved, followed by dictation time, recordings, days dictated and the average time to text, in a grid that adapts to the window width. A short note at the foot says that only counts are used, never text or audio. The period chips and the "Try again" button have stable ids for UI flows. Works the same on macOS, Windows and Linux.
- **Smart Mode shows what a preset does:** under the standard preset, a sample box now shows the same raw sentence and its result for Off, Cleanup and Concise (Translate depends on the target language, so it has no sample). The download, cancel, delete and shortcut buttons in the section carry stable test IDs. Works the same on macOS, Windows and Linux.
- **Dictionary: one way to add a term or a replacement:** under the Terms bar, a new switch "Often misspelled as …" turns Enter into a replacement (wrong spelling, then the correct one); without it Enter adds a term. Entries are checked with a clear reason and next step (at most 60 characters, at least one letter or digit, no duplicate, and a term cannot already be the trigger of a replacement); a term that is also a trigger is marked "Also a replacement" in the list, and Escape leaves the mode. The empty list offers example terms that fill the bar with one tap. Works the same on macOS, Windows and Linux.
- **Error and hint cards offer the fix directly:** a missing speech model now leads with "Download now" (Settings is the second button), a failed quick note offers "Copy text" and "Open Notes", the wrong-language card names its target ("Switch to DE", it stays switched), and turning on "Tap or hold" from the short-press card is confirmed at the pill. Works the same on macOS, Windows and Linux.
- **Recordings list: J and K move the cursor:** in the Recordings list, J and K now move down and up like the arrow keys (not in a text field, not with Cmd, Ctrl, Alt or Shift). The shortcut help lists them. Works the same on macOS, Windows and Linux.
- **Hotkey disturbances also show up inside the app (macOS):** when secure keyboard input (for example a password field) or another app that checks every key press slowly disturbs the hotkey, WhisPaste now shows the same hint as a message in the app window, next to the system notification, so you see it even with system notifications switched off. The message names the app when macOS tells it and says what to do. The same cause is shown at most once every 30 minutes; there is no new setting. Windows and Linux have no such system signal, so nothing changes there.
- **Keyboard-observer problems show up in the log (macOS):** when macOS switches off the key observer behind a single-key hotkey (too slow, or blocked by another keyboard tool) and WhisPaste turns it back on, the log now says so, with the reason, a running count and the time since the previous time, at most one line per 30 seconds. Starting and stopping the observer is logged too. Only state and counters are written, never what you type. Windows and Linux use no such system-disabled observer, so nothing changes there.
- **Snippets have a trash and favourites:** deleting a snippet now moves it to the trash ("Trash" under "Filter" next to the search) instead of removing it for good. You can restore it, delete it for good or empty the trash, and the usual "Undo" stays. Snippets in the trash stay out of the picker and the settings export, and are removed after the period set under "Empty trash after". A star on each row marks favourites, which are listed first.
- **The idea button says it leaves the app:** "Submit an idea" on the overview now carries the same external-link mark as the other web links and asks first ("Continue" or "Cancel") before it opens the public ideas board in your browser. Works the same on macOS, Windows and Linux.
- **Newsletter sign-up works the same for every address:** after every sign-up the app says "Check your inbox and click the link in the email" (it never reveals whether the address is already on the list). If the link expires or is no longer known, the card shows a calm note to sign up again instead of silently returning to the form.
- **"Restart" on the cards that ask for one:** when the speech model cannot start, the speech recognition needs a fresh start, or the hotkey stopped responding and could not be restored, the card now has a "Restart" button (next to "Open settings" for the model). WhisPaste comes back in the same state; settings and history are kept. A running dictation is never cut off: the restart waits until it is finished. Works the same on macOS, Windows and Linux (on Linux an AppImage starts again from its image file).
- **Sort, group and filter your notes:** the Notes list can be sorted by title, date added or date changed (and reversed), grouped under Today, Yesterday, This week and Older, and filtered by one or more tags (a note must carry all of them). Favorites stay on top, and your sort and grouping are remembered.
- **Notes list: tag suggestions, foldable favorites, hit list:** the tag field of a note now suggests the tags you already use (your most used ones when it is empty, matching ones while you type); pick one with the arrow keys and Enter. The Favorites section of the list has a heading you can click or press (Enter or Space) to fold it; your choice is remembered, and folded favorites are skipped by the arrow keys. A search now shows a hit list instead of the grouped list: notes whose title matches come first, then tags, then text, with no favorites on top and no date headings, and the search also looks at a note's title. Works the same on macOS, Windows and Linux.
- **"Try again" shows that it is working:** after you click it on the error card, the overlay pill now shows the same processing state as after a normal dictation until the text is inserted or an error card appears, instead of staying idle. The state always ends, also when the attempt fails.
- **"Try again" after a failed transcription also pastes:** the button on the error card now transcribes the kept recording and inserts the text like a normal dictation, instead of only saving it to your recordings. The text goes to the app that was in front when you pressed the button; if you switched apps meanwhile, nothing is pasted and the paste card offers "Paste text again", and while a new dictation runs the text is saved to Recordings only. If it fails again, the card offers "Try again" and "Open in Recordings". The three buttons that stop a dictation and paste it (lost microphone, time limit, quiet microphone) now share one label, "Finish and paste", because they do the same thing. Works the same on macOS, Windows and Linux.
- **Notice cards offer the right second step:** an error card can now carry two buttons, the fix and "Try again" (for example Try again next to Open Settings after a failed transcription), and a failed paste offers "Paste text again" next to its fix. One label means one effect everywhere: "Choose microphone" opens the microphone setting, "Open System Settings" opens the operating system's own settings, "Open GPU settings" opens the GPU row. Works the same on macOS, Windows and Linux.
- **Filter recordings by period and length in one click:** the Recordings filter offers Today, Yesterday, Last 7 days, Last 30 days (calendar days, including today), This month and Any time; length is filtered with the duration choices in the same panel. The period choices replace the old "Today" and "This week" filters. The period choices write the search operator `date:` into the search field; `date:`, `longer:` and `shorter:` can also be typed, combine them with words, tags and language, and remove each one with its pill. The result counts follow the filters. Works the same on macOS, Windows and Linux.
- **A note and the recording it came from know each other:** "Take over as note" now remembers the recording. The note shows "From recording of ..." and jumps back to it; the recording shows "Taken over as note" and jumps to the note. If either one is deleted or moved to the trash, the link on the other side just disappears. Works the same on macOS, Windows and Linux; existing notes are not changed.
- **Hold, tap and double tap stay right on a busy computer (Windows and macOS):** for modifier-only hotkeys (such as a single Ctrl, Alt or fn key) the decision now uses the time the system recorded for the key press, not the moment WhisPaste got around to look at it. A short stall no longer turns a hold into a tap. Same as already on Linux (X11).
- **Undo by keystroke on Windows:** after an edit by voice that changed names, "Undo" now reverts the insert in the target program itself with Ctrl+Z, as long as you have not typed or clicked elsewhere since and the program is still in front; in consoles, unknown programs or when in doubt, the original text goes to the clipboard as before. Inserting does not wait for this: if the watch on keys and clicks was not running yet when the text went in, that insert also takes the clipboard path.
- **Undo by keystroke on Linux (X11):** the same undo as on Windows, in X11 sessions. After an edit by voice that changed names, "Undo" reverts the insert with Ctrl+Z, but only in known text programs and only as long as you have not typed or clicked elsewhere since. Terminals, unknown windows and Wayland sessions take the clipboard path as before: under Wayland no Ctrl+Z is sent, because WhisPaste cannot reliably tell which window is in front there. Right before sending Ctrl+Z, WhisPaste checks once more that the program is still in front and known; if it is not, or if you typed or clicked elsewhere in the meantime, "Undo" copies the original text instead. No extra confirmation appears after a sent Ctrl+Z. On macOS, "Undo" keeps putting the original text on the clipboard.
- **Undo by keystroke on macOS:** "Undo" after a selection edit with a renamed term now presses Cmd+Z in the app you dictated into when it is a known text app and you neither typed nor clicked elsewhere since the insert (the click on "Undo" itself does not count); in terminals, unknown apps or after any other input it copies the original text to the clipboard as before. Windows and Linux (X11) already behaved this way.
- **You are told when the history move or its safety copy fails:** if WhisPaste cannot move the history to its new folder at start (it keeps using the old location), or cannot write the safety copy before a storage update, a notice now says so, what stays in use and what to do next, instead of only writing to the log.
- **Add a corrected word to the dictionary in one step:** after you correct a word in a recording and save, a notice under the entry offers "Add to dictionary". One click adds the corrected word to the terms; a word that is already there is not offered. It works with the keyboard and the same way on macOS, Windows and Linux, and nothing leaves your computer.
- **Terms as a list with a search and add bar:** the Terms tab in the Dictionary now shows one row per term instead of one text field. Type in the bar on top to filter the list, press Enter to add the typed text as a new term (Cmd+F or Ctrl+F jumps to the bar). Every row has an edit and a delete button; deleting happens at once and an "Undo" message brings the term back. A term that is already there, in any letter case, is not added twice. Your existing terms and their separators are kept as they are until you change something.
- **The terms list shows where the recognition stops using your terms:** with on-device Whisper (exact count of the loaded model) or Deepgram, a line "From here on the recognition no longer uses the terms" appears in the Terms list and the terms below it are dimmed. The order is the priority, and every term except the first has a "Move up" button (not while searching), so you can put the important ones first without dragging. The "about … of … used" counter is gone.
- **Recording text saves itself while you edit:** the text of a recording is now saved a moment after you stop typing, when you leave the field and when you open another entry, so a crash or a mis-click no longer loses it. A small label next to the text shows "Saving…" and "Saved"; screen readers announce only a failed save, which shows "Not saved yet" and leaves the text in the editor. The editor stays open until you press Save; Esc still throws the edit away after asking and brings back the text from before. Same on macOS, Windows and Linux.
- **A speech model that fails to load repairs itself:** WhisPaste now tells a damaged model file from a graphics card that cannot run the model. A damaged file is checked against its known fingerprint and downloaded again only if it really differs. A graphics card that cannot run the model switches to the processor with a short note, and WhisPaste remembers this until the graphics driver, the system or WhisPaste is updated (a timeout or busy video memory only affects the current session); "Check again" under Settings > Speech recognition resets it. The damaged-file repair works the same on macOS, Windows and Linux; the remembered GPU verdict applies on Windows and Linux only, on macOS the existing crash protection keeps handling Metal.
- **Version history for very long notes:** long notes now keep their versions (stored compressed), the newest 20 versions are kept even above the size budget, and saving a version no longer reads the whole history. Versions of long notes are stored compressed, so an older app version shows them as text it cannot read; do not go back to an older version after saving such versions. If a note is too long for versions, you now see a notice instead of silence, also when you leave the notes page first; the text itself stays saved. All versions of one note together never exceed 16 MiB, and a single version holds at most 2 million characters.
- **Offer another microphone when the input is silent:** when a recording delivers only silence, the overlay card now offers the best other microphone as a "Use <microphone>" button. One click switches; nothing switches on its own, and a microphone you chose yourself is never replaced. Other inputs are ranked: cable and USB microphones first, then the built-in one, then devices with unknown names, Bluetooth last. Phone and virtual inputs are never suggested. The suggestion needs the device name, which the app now reads with the system default input on macOS, Windows and Linux; only when the system does not name it, the card shows just "Change microphone". With the lid closed, macOS and Linux no longer suggest the built-in microphone; Windows has no way to ask for the lid, so there the silence detection decides.
- **The hotkey names what disturbs it (macOS):** when secure keyboard input (for example from a password field) or another app's keyboard tap slows the hotkey, a quiet notice names the cause and, where macOS tells, the app. Each cause and app is named at most once every 30 minutes. WhisPaste does not change the other app; the manual (chapter 14) explains what to do. Windows and Linux show no such notice, because the systems offer no equivalent signal.
- **Keep apps out of the clipboard history:** under Settings → Appearance, with the side panel on, "Excluded apps" lists apps whose copies normally do not enter the clipboard history (entries already there stay; on macOS the app is taken when WhisPaste notices the change, so a quick app switch can misattribute a copy). Password managers are pre-filled; add more by name or pick them from the running apps (macOS and Windows). Linux cannot tell which app a copy came from, so there the list does not apply; copies that password managers mark as confidential can be skipped instead.

- **Overlay options that a size does not show are greyed out:** Mini and Nano draw no timer or cancel symbol, and Nano no live text, so "Show timer" and "Cancel symbol" (and "Live transcript" in Nano) are now disabled there, each with a short note (also for screen readers, and reachable with the Tab key). Nano no longer runs the live transcript in the background. Your choice is kept and applies again in Normal and Compact. Same on macOS, Windows and Linux.
- **The start of a dictation fits the text before it:** when you dictate in the middle of a text, WhisPaste adjusts the first letter and the space to what stands in front of the cursor, on macOS, Windows and Linux. Names and dictionary terms stay as they are, and Recordings keep your original text. If the field cannot be read in time, the text goes in unchanged. Turn it off with "Fit the start of a dictation to the text". Not available in the Mac App Store version, whose sandbox cannot read other apps' fields.
- **The floating button shows the WhisPaste wave mark when idle:** at rest, the button shows the wave mark in the foreground colour of its look instead of a microphone. With the slim capsule, moving the mouse over it fades to the microphone, and moving away fades back. With reduced motion it switches without animation. Recording, transcribing, results, errors and the locked state keep their own icons. Same on macOS, Windows and Linux, except that Wayland has no hover, so the capsule keeps the wave mark there.
- **White wave for the overlay:** the wave colours under Settings > Overlay now include White, a clearly readable choice on the dark backgrounds. It is not available on the light backgrounds, where it could not be seen. If you switch to a light background, the wave moves to Cyan and a short message says so. Works on macOS, Windows and Linux.
- **Assign recent apps to a profile with one click:** the Target apps section of an app profile lists the apps you recently dictated into, with name and icon, newest first. One click assigns an app. Apps that already belong to a profile, and WhisPaste itself, are left out; typing an identifier and "Capture app" still work for apps you have not dictated into. Works on macOS, Windows and Linux (on Wayland the target app is not detected, so the list stays empty).
- **Choose your sound profile:** under Settings > Recording > Sound & feedback you can pick "Classic" (the original tones) or "Amber" (the new default). The choice applies at once, without a restart, and a short sample plays when the sound is on. Works on macOS, Windows and Linux.
- **Learning log in the Suggestions tab:** a collapsible "Learning log" below the suggestions lists every correction WhisPaste has noticed, also those seen only once, with where it came from (voice command or an edit under Recordings), how often, when, and why nothing is suggested yet (for example a replacement or term already exists). Single entries can be removed. The texts say plainly where WhisPaste learns: the voice command, an edit under Recordings, and fixes made right in the target app.
- **Learning from corrections in the target app, also in terminals:** with "Learn from corrections" on, WhisPaste watches the text it just pasted for up to a minute and learns from words you correct there, in editors, browsers and terminals. You can click anywhere inside the text; each corrected word counts on its own, while words you add, delete or write on after it do not. A change of capital letters counts only inside a sentence, where it marks a name. Only the pasted section is read, never the whole document and never password fields; nothing leaves this computer or appears in logs. Works on macOS (direct download; the Mac App Store sandbox does not allow it), Windows and Linux. The learning log marks these corrections as "Fix in the target app" and shows for the last target apps whether WhisPaste could follow your changes or why not, for example the Mac App Store sandbox or a missing Accessibility permission.
- **Deleting is reversible:** deleting a snippet no longer asks first; it disappears at once and an "Undo" message brings it back exactly as it was. Notes in the trash are now removed automatically after the same period as recordings ("Auto-delete trash after" under Privacy & data, never if unlimited); notes already in the trash are kept for one full period from the first run. Undoing a bulk delete or archive in the history no longer changes the other state of an entry (an archived entry that was trashed stays archived).
- **Back to the app after confirming the newsletter:** after you click the link in the confirmation email, the page offers "Back to the app", and the overview shows that your sign-up is confirmed, with the date. Until then the app asks the WhisPaste server only while a confirmation is pending, when you return to the window, at most every two minutes (the link back from the confirmation page asks at once), using a one-time code that never contains your address. Works on macOS, Windows and Linux in every package.
- **Newsletter sign-up on the overview:** "Get involved" now has an email field with consent checkbox and "Sign up". The app sends the address to the WhisPaste server only when you press the button and never stores it; you are signed up once you click the link in the confirmation email (double opt-in). Clear messages for an incomplete address, too many attempts and no connection.
- **Get involved on the overview:** a "Get involved" section at the bottom of the overview. Two cards for the project's GitHub repository and YouTube channel show their stars and subscribers when the server has the numbers; the app asks at most once a day, and only while the overview or the support page is open. Without a number, a card says what its link is for. Below them, "WhisPaste support" opens the page listing what each build offers; direct downloads also link to the ideas board, store versions to the rating in the store. The developer's own X and GitHub profiles sit in a separate group, "From the developer". It is on by default and can be hidden with "Hide this section" or under "Customise overview". Store builds no longer show the GitHub invitation; this section takes its place.
- **Storage and last dictation on the overview:** two optional blocks next to the figures. "WhisPaste storage" shows the space used by speech models, recordings and the cache, and "Clean up…" empties only the cache after asking; models and recordings are never removed there. "Last dictation" shows whether the last dictation ran on the processor or the graphics card, how long the transcription took, and a note when the graphics card was intended but did not take the work. Both are switched on by default and can be turned off under "Customize overview".
- **System load on the overview:** an optional card, off by default, switched on under "Customize overview". It shows the load of the whole processor, the memory in use and the free space on WhisPaste's drive. The values are read only while the overview is open and the window is active, never in the background or during a dictation. A note appears in the card when memory runs low or the drive is nearly full.
- **Overview start page:** WhisPaste now opens on "Overview", the first entry in the sidebar. It greets you with your dictation keys, shows one missing setup step only when something needs attention, keeps the first steps card, and shows words, words per minute and time saved for this week or in total, the dictation days of the week, and your five newest recordings with copy and open actions. A discovery tip appears once a day and can be closed or turned off, and "New in this version" replaces the old feature spotlight pop-up.
- **First steps on the start page:** after onboarding, the start page shows a card with four steps: dictate into another app once, find a recording and copy it, add a word to your dictionary, and dictate a note. A step is ticked only when it really happened, never by a click, and nothing changes while a recording runs. The first step counts as soon as a dictation went to another app, also when WhisPaste only copies the text instead of pasting it, and earlier dictations count too. Close the card at any time; "Show again" under Settings > General brings it back. Existing installs never see the card.
- **Recordings show the app they went to:** each recording names its target app with the app's own icon and name, as the system knows them ("Windows Terminal" instead of "WindowsTerminal"). Apps the system cannot name get a tile for their kind (terminal, browser, editor, chat, mail, notes, office, calendar, design). Icons are cached on this computer and deleted together with the recordings.
- **Feedback & contact in Help:** a new Help tab, "Feedback & contact", holds every way to reach the team: the feedback form, reporting a problem, ideas (form or the public voting board) and the contact address. "Contact us…" in the Help menu (macOS menu bar, title-bar menu on Windows and Linux) opens this tab; "Send feedback…" in the tray menu still opens the form directly. The "Contact us" card stays at the top of the other Help tabs.
- **Clearer support page:** Help > Support now shows only ways to support WhisPaste, grouped into one-time (PayPal without an account, Ko-fi, Buy Me a Coffee, store purchases), monthly (GitHub Sponsors, also for companies) and free ways (rate, star on GitHub with the current count, share). Each provider has its own tile with its logo and colours. Store versions show only what the store allows.
- **Glass overlay background:** a fifth background for the overlay, "Glass": a nearly colourless body whose text follows the system appearance. On macOS 26 and later and on Windows 11 the system's own glass or acrylic shows through; on Linux and older systems it is a faint neutral tint.
- **Notice card in the overlay:** when the microphone is missing, fails to start, loses its signal, stays very quiet, or the duration limit is near, the overlay grows into a small card that names the problem and offers a way out: "Choose microphone", "Try again", "Record {n} more min" (extends the limit once by the set duration) or "Finish and paste". No button throws away what you said: each either keeps recording or stops and transcribes. "Choose microphone" during a dictation opens Settings at the microphone once that dictation is pasted; the new microphone applies from the next one. The card never takes focus from the app you type in, and screen readers announce it. The quiet-microphone card also offers "Finish and paste", so a dictation can always be ended by mouse; the hint itself is turned off and on under Settings > Overlay.
- **Nano overlay size:** a fourth overlay size, 88 × 24 px: a short live wave and a spinner, check or error glyph, with no text and no timer. Choose it under the overlay size settings or from the overlay's right-click menu. Every shape, background and wave style of the smaller sizes works in Nano too.
- **The overlay names where the text went:** after a confirmed paste the overlay and the dock say "Pasted into Slack" instead of just "Pasted", with the app's name as the system knows it. Unconfirmed, failed or blocked pastes never name an app, and the name is never stored.
- **Two new wave styles, all styles redrawn finer, and a wave that uses its whole height:** "Ribbons" draws your voice as soft, overlapping bands that swell with the level and carry it in from the right; "Pulse" is a centre orb whose soft stages carry each word outward, the outermost one faintest. "Line" is one filled silhouette of your voice, lit from the centre, and "Dots" is a fine dot grid with the rhythm of the bars, whose dots grow in place; both fade from older sound to "now". No wave style draws outlines any more, so they stay as calm as the bars, also in a black wave colour. Every wave style now adapts to your voice and microphone: normal speech runs from rest to full height, quiet and loud syllables differ clearly, and a quiet microphone looks like a loud one instead of staying a small strip. All styles move only with your voice, so they stay calm with reduced motion, and they use the wave colour and its contrast rules. Choose them under the overlay's "Wave style"; saved styles keep working.

- **Own OpenAI-compatible endpoint:** speech-to-text and Smart Mode can use a server you choose, such as LM Studio, Ollama or llama.cpp, or a third-party provider. Enter the address (ending in /v1), an optional key and the model name, then check the connection with "Test connection" (it only asks for the model list, no audio or text). Settings show where the data goes: a server on this device or in your local network stays local, any other server receives the audio or text. Plain http is accepted on this device and in the local network, with a warning that other devices there can read it; servers on the internet need https. The transcription path is fixed to /audio/transcriptions.

- **Time left before the duration limit:** in the last 30 seconds before the recording stops at its duration limit, the overlay shows the remaining time in amber instead of the elapsed time. Without a limit ("Unlimited") nothing changes.

- **Key hints in the overlay:** the normal recording pill names the stop key next to the stop square and the cancel key (Esc, or F12) next to the close glyph. Compact and mini stay without hints, and a hint is left out when the waveform would have no room left.

- **No pulsing dot while recording:** the live wave, the running time and the stop square already show that the microphone is on, so the recording pill drops the dot. The timer starts after the close glyph, and the pill is narrower by that space. The overlay no longer runs a permanent pulse animation while recording, which saves CPU. Done, error and transcribing keep their icon and spinner.
- **Rounded rectangle keeps its corner share:** the corner radius is a share of the height, so the compact and mini rectangles no longer look almost like pills.
- **One level bar element:** the microphone test in onboarding and the recording overlay draw their bars with the same element. The newest bar is marked as the "now" bar; the overlay used to mark its last five bars.

- **Too-quiet hint:** when the microphone stays very quiet for five seconds during a recording, the overlay says "Microphone very quiet" in place of the timer. Recording keeps running, and the hint goes away as soon as the level comes back. Digital silence keeps its own "No microphone signal" notice.

- **Long recordings resume:** a long cloud transcription shows "Processing part k of n" in the dock and the overlay. Each finished part is kept on this device, so after a crash or quit only the part in progress is transcribed again at the next start. Saved parts are removed together with their recording. Local models do not split recordings and are not affected.
- **RAM check before a large speech model loads:** when you pick a local speech model that clearly needs more memory than is free right now, WhisPaste asks "Load anyway?" with Cancel and Load anyway. Cancel keeps the current model. Nothing is blocked, and unknown free memory never triggers the question. At start, a model that does not fit the free memory gets a one-time notice, and the model still loads.
- **Turn recording storage off:** "Save recordings" in the Recordings settings (on by default). When it is off, a dictation is only pasted or copied: nothing is written to Recordings, no audio is kept, and the rating reminder and statistics keep working. Existing recordings stay until you delete them with "Delete recordings", which asks first. Recordings that failed to transcribe can still be copied from the recovery list, but are not saved as new entries.
- **Written forms in dictation:** spoken e-mail addresses, web addresses, dates, clock times and amounts of money in German and English are written as usual, for example "max at gmail dot com" becomes max@gmail.com and "zehn Uhr dreißig" becomes "10:30 Uhr". Each of the five kinds can be switched off under Settings > Text processing; the switches are on for new installs. Existing installs keep the stage off until they switch it on, and a stored choice is never changed. Other languages are not changed yet.
- **Stop sign on the floating button:** while recording, the floating button shows a stop square instead of the microphone and a ring around its edge. Screen readers announce it as "Stop recording".

- **Slim idle capsule for the floating button:** with "Slim capsule when idle" on (off by default), the idle button rests as a narrow capsule and opens to the full pill with the microphone while you hover over it. Recording and results keep the full button. Under Linux with Wayland, where no hover is tracked, the capsule stays narrow and a click still starts recording.
- **Hold to record is the default:** new installs start with "Hold to record" on, so the hotkey records while it is held and releasing it inserts the text. Existing installs keep their setting. Without key-up support (some Linux sessions) recording stays in toggle mode, and the onboarding texts say so.
- **Drag entries out of the quick-paste panel on Windows and Linux:** as on macOS, a text or image entry can be dragged from the panel straight into another app. Text arrives as text; on Windows an image arrives as PNG plus a bitmap for apps that only take bitmaps, on Linux in whichever image format the target asks for. After a drag the panel answers clicks again right away.
- **Hotkey gestures:** the dictation key can work as hold-or-tap: holding it longer than a threshold (default 250 ms, existing installs keep 1000 ms) acts as push-to-talk, a short tap toggles. Double tap runs its own action (hands-free, quick note or snippet picker). A single modifier key (right Control, right Alt or Option, right Command or Windows, or Fn on macOS) can serve as the dictation key. On macOS, WhisPaste asks for Input Monitoring first and explains why. Modifier-only keys and double tap are not available under Wayland.
- **Redesigned main window:** a sidebar leads to Recordings, Notes, Dictionary, Snippets, Statistics and Help, and a dock at the bottom holds the Dictate button with the speech model, Smart Mode, language and output selectors.
- **Import audio files:** drop a file onto the window or the Recordings page to transcribe it on this device. WAV works everywhere; MP3, FLAC, M4A/AAC and Ogg/Opus work on macOS, Windows and Linux. While a file is transcribed, its row shows the progress in percent with Whisper, otherwise the elapsed time.
- **Notes:** write notes with titles, images and highlights, keep a version history, lock them behind the History PIN, and save quick notes in the background.
- **App profiles:** a profile sets the language, speech model, Smart Mode preset, microphone and after-transcription action for a target app, and can have its own hotkey. Pick it from the tray or the menu bar, or let rules activate it.
- **Dictionary and Snippets pages:** the Dictionary holds terms, replacements and suggestions, with a CSV import preview. Snippets can be marked as favourites and show how often they are used.
- **Undo Smart Mode:** undo or restore a Smart Mode result from History. Output that changes facts or loops falls back to the raw transcript.
- **Menu bar and title menus:** macOS gets a native menu bar with Recording and Help menus, and Cmd+, opens Settings. Windows and Linux get the same commands in a title bar menu.
- **Help hub and feedback form:** the 16-chapter handbook, support, introduction and diagnostics share one searchable Help page. The feedback form offers type chips, an optional rating and opt-in diagnostics, and opens from the tray.
- **Linux auto-paste on Wayland:** WhisPaste checks the focused window, confirms each paste with a clipboard receipt, and lets you choose the uinput keyboard or the desktop portal.
- **Recent recordings in the tray:** the tray menu lists the last five recordings with their time and the start of the text, and one click copies the text. With a History PIN set, the items show the time and word count instead of the text, and while recordings are locked the entry offers "Unlock recordings…".
- **Feedback quotes with consent:** the feedback form can show your praise anonymously as a quote on the website, but only if you tick a box that is off by default. Only the type Praise offers the box; bug reports and feature ideas are never published. Withdraw it with one click on the feedback page; a withdrawal made offline is sent once WhisPaste is back online.
- **App profiles in Settings:** a new Profiles area lists the app profiles, and a detail editor sets what a profile changes for one app. The app in front is recorded when a dictation starts, and the manual explains how profiles apply. Profiles can be saved, deleted and reordered.
- **Honest paste result:** when WhisPaste cannot confirm that the text landed in the app, the overlay and the dock say "On the clipboard" instead of "Pasted". On macOS, the paste notice also says that macOS does not paste automatically into password and PIN fields and that the text must then be pasted by hand.
- **Hotkey conflict warnings with one next step:** the hotkey recorder and the dictation key dialog name the system function that reserves a combination, and say what to do: pick another combination, or switch the system function off. On macOS, a double tap of Fn is flagged as system dictation with the path to turn it off. On Windows, Win+H (voice typing) and Win+V (clipboard history) are flagged. The warning never blocks saving.
- **GitHub star invitation:** after 40 recordings, store builds invite you to star WhisPaste on GitHub, at most twice and 30 days apart. Settings and Help keep a permanent entry.
- **Dictionary CSV import review:** the review lists each row with its planned outcome (added, already present, conflict, circular reference). A conflict follows the strategy you choose (skip, overwrite or keep both). Rows can be unticked, and the import is written in one transaction.
- **Dictionary CSV export choice:** the export lets you choose which entries go into the file. The file carries the package name and the export date in its metadata line.
- **Floating button on Linux:** Settings offers the floating button on Linux. Where the desktop cannot run it, the switch is disabled with an explanation. On Wayland the section names the limits: the desktop decides the position and whether the button stays on top.
- **Coffee button:** a yellow "Buy me a coffee" button sits under the version in Settings, at the top of the Support tab, and in the tray menu. Direct builds offer Ko-fi and Buy Me a Coffee; store builds open the store's own one-time purchase, and the button stays hidden where the store cannot sell it.
- **Hold or tap threshold:** with hold-or-tap on, a press shorter than the threshold toggles recording and a longer press dictates while held. The threshold (150 to 1500 ms, default 250 ms) is set in Shortcuts. Existing installations keep 1000 ms.
- **Deepgram learns your terms:** the custom vocabulary from Dictionary → Terms goes to Deepgram as keyterms, so names and jargon come out right more often in cloud dictation. At most 50 terms and 500 bytes per request.
- **Symbol templates for replacements:** a new entry in the replacements overflow menu adds ready-made rules for dictated symbols such as "klammer auf" or "at sign". Triggers that already exist are left untouched, so running it twice adds nothing.
- **Learns words and terms from repeated corrections:** when you make the same correction twice, with the "correct: …" voice command or by editing a recording's text, Dictionary → Suggestions offers it as a replacement or as a term. Nothing is added without your choice, a dismissed suggestion never comes back, and the switch for learning sits on the same tab.
- **Upgrade backups of the history:** before a database upgrade or the move from the old nested folder, WhisPaste keeps up to three verified copies of the history in `history-backups/` (at most 512 MB together). They are dropped after three clean starts or seven days at the latest, and at once by factory reset, the forgot-PIN wipe and "Delete all recordings". Like the database itself, the copies are not encrypted.
- **Overlay notice card closes with the cancel key:** while a notice card stands and no dictation runs, Escape (or F12, as chosen in Settings) closes it without clicking and without taking focus from the target window. The close button now has an accessible name. A notice the overlay cannot show (overlay off, guided snippet running) is logged and appears as a banner in the main window instead of being dropped. If the card has a button, the other key (F12 or Escape) presses its first button; that button names the key. The keys are claimed only while the card stands.
- **Overlay notice card follows fixed rules:** a card has at most two text buttons plus the cross, never a text button "Close". The cross only hides the card; while a recording runs behind it, it reads "Hide hint" and the recording goes on. A footer names the valid keys: "Esc: discard" while you dictate, "Esc: close" otherwise. Errors, notices about lost text or a dead hotkey, and every notice with a button stay until you close them; pure status and success notices close after a time that follows their length. An error card stays after the short error reset until you close it or start a new recording.
- **Transcribe a history entry again:** the entry menu has "Transcribe again" for every entry outside the trash whose audio is still saved. The new text is shown first and replaces the old one only after you confirm. Without saved audio the item is greyed out and says so.
- **Website contact widget answers questions:** ask a question in your own words and the widget shows the matching FAQ answer, offers at most three FAQ entries to choose from, or opens the email form with your question already filled in and still editable. The greeting appears once per browser and the badge only until you first open the widget, on phones too. Without JavaScript the page shows the contact address as a mail link. Available in all 8 website languages (#352).

### Improvements

- **Sorting and "Select all" reach every recording:** On Recordings, "Oldest" and "Longest" now show the oldest or longest recordings of your whole history first, not just of the rows loaded so far, and keep that order as you scroll. "Select all" (and Ctrl/Cmd+A) selects every recording the list or search holds, up to 10,000, and the bar counts all of them; copy and export include the ones further down. Same on macOS, Windows and Linux (#1663).
- **Large histories stay light:** WhisPaste no longer keeps every recording in memory. The tray, the side panel and the Overview read only the recordings they show, figures and filter counts are counted by the database, and Recordings loads search results, pinned entries and duration filters page by page as you scroll, just like the full list. Everything stays reachable and the results look the same. The side panel lists your newest 200 recordings; the full search stays on the Recordings page. Works the same on macOS, Windows and Linux (#1643).
- **Calmer spacing and depth across lists and settings (#280):** small gaps in history, notes, profiles, settings, the side panel and filter chips now follow the shared spacing scale, the dock's dropdown menus use one named elevation, and the embedded hotkey card in onboarding no longer casts a shadow, so only floating panels lift off the page. Same on macOS, Windows and Linux.
- **Word import review sits on the shared page frame:** the page that lets you tick imported words no longer adds its own safe-area inset, so its title and spacing match every other page; the learning log's first load and the supporter confirmation's live region are covered by tests (#618).
- **Clear favorite star in the language picker:** the star now sits in the corner of each language tile, filled for a favorite and outlined otherwise, and screen readers announce it as on or off. Once the maximum number of favorites is reached, the remaining stars are dimmed and their tooltip says why. "Selected" no longer repeats a name ("Deutsch / Deutsch") or shows a bare language code as a second line. Same on macOS, Windows and Linux (#1206).
- **Easier install on the Mac:** the download page sends Mac visitors straight to the Mac download and explains the install in three numbered steps, and the disk image window shows the WhisPaste icon with a clear "drag to Applications" hint.
- **Dictionary dialog scrolls in one place:** with many triggers on one entry, the trigger rows no longer sit in a small scroll box of their own inside the dialog; the whole form scrolls once, and a newly added trigger field scrolls into view. The last raw spacing values in Statistics, History, Smart Mode and the speech model picker now use the shared spacing scale. Same on macOS, Windows and Linux (#1368).
- **The permission helper shows what to do (macOS):** the small panel next to System Settings now shows a short animation without text: the WhisPaste row, and its switch turning on. With "Reduce motion" it shows a still picture instead. The Mac App Store and the direct download show the same picture; in the direct download you can still drag it into the list if WhisPaste is missing there (#753).
- **One look for icon buttons, progress bars and cards:** the remaining hand-built icon buttons in History, the dictionary and the tag dialog, every download and import progress bar, and the cards on Statistics, Feedback and Support now use the shared building blocks, so they have the same size, focus ring, tooltip and rounded shape everywhere (#279).
- **Dictionary suggestions say what is going on:** while suggestions load, the tab shows placeholder rows instead of claiming there are none; if loading fails, it says so, suggests what to do next and offers "Try again". Each suggestion now has two quiet buttons to keep it and a separate "Reject", and a rejected suggestion can be brought back with "Undo" from the notice it leaves. Works the same on macOS, Windows and Linux (#321).
- **Consistent motion and corners:** one-shot animations use the shared motion timings, and the largest corner radius now sits on the 4 px grid (20 instead of 22 px), matching the design tokens. Loop animations and the onboarding sequence keep their documented timings (#1369).
- **Statistics lead with one key figure (#1075):** the words you dictated open the page as a large figure of their own; the other figures follow in tiles of equal height. Section headings read clearly in every appearance, and the recording-length chart uses the app's accent colour instead of a separate violet.
- **History, archive and trash no longer load full texts (#1324):** each recording keeps a short preview in its own column, computed when it is saved, and the lists read only that preview, titles, flags and times. Saving a very long recording no longer re-reads every text, and existing recordings get their preview in small steps on the first start. Copying, exporting, pasting from the side panel or the tray reads the full text of just that recording. Sorting by "longest" now uses the recording duration.
- **Saving long notes no longer reloads every text:** the notes list and the trash read only title, a stored preview (computed on every save, new column, existing notes are filled in on update) and flags; the full text is read for the open note only, and during a search for the matching notes. Saving a note with 20,000 words keeps the list instant. Works the same on macOS, Windows and Linux (#639).
- **Fn as hotkey warns about the 🌐 key setting (macOS):** when you record Fn as your dictation key and macOS is set to open emoji, switch the input source or start system dictation on "Press 🌐 key to", the recorder now names that action and offers "Open keyboard settings", where you can choose "Do Nothing". WhisPaste only reads this setting and never changes it; if it cannot be read, the general Fn warning shows. Windows and Linux have no Fn hotkey, so nothing changes there (#778).
- **One page frame and reading width:** every page now uses the same margins, and long text (Help, Feedback, recording details) stops at one comfortable reading width instead of each page using its own. Help's tabs sit directly under the title without an empty band. The dock's labels are no longer in capitals, its values and main button are easier to read, and its controls are at least 48 px tall. Same on macOS, Windows and Linux (#197).
- **macOS download page names all three permissions:** the macOS card on the download page now lists Microphone, Accessibility and Input Monitoring with one sentence each on what they are needed for (Input Monitoring: single-key hotkey and noticing a lost key-release event), in all 8 website languages.
- **Input Monitoring in the permissions overview:** Settings > Privacy now lists Input Monitoring next to Microphone and Auto-Paste, with its status, one sentence on what it is for and the action that fixes it. It is only needed when a single key starts dictation; with a key combination it reads "not needed". The status updates live when you change it in System Settings, and the button opens System Settings with the same "drag the app into the list" helper as the first-run setup. Windows needs no such permission; Linux names the X11 session the single key needs (#1198).
- **Snippets in the same layout as Recordings:** click a snippet to read its full text beside the list, without a dialog; edit, copy, star, duplicate or delete it from the detail header, Esc closes it. Active/Trash sit under "Filter" next to the search, the select and sort tools at the end of the same row (one "More" button on a narrow window). Replacements share the frame, so their sort and "More" buttons moved to the second row. Holds at 800 px, 130 % text and right-to-left (#1184).
- **Compact support buttons:** on Help > Support, the GitHub Sponsors, Buy Me a Coffee, Ko-fi and PayPal buttons are now only as wide as their content and sit side by side instead of as half-page bars. In a narrow window or with large text they move to the next line; the "Monthly support" and "One-time support" groups and their order stay the same (#1070).
- **Recordings page in a fixed layout:** search, "Filter", the select, sort and view tools and the "New" button in one row (one "More" button on a narrow window), list on the left and detail on the right. Notes and Snippets will follow the same layout. Spacing mirrors correctly in right-to-left languages, and the page holds at 800 px width and 130 % text size on macOS, Windows and Linux The period and duration choices appear only once there are recordings or a filter is active (#1176).
- **macOS: no keychain password prompt for new secrets:** API keys, the automation token, the data key and the feedback consent saved from now on go to WhisPaste's own keychain area, shared by the direct download and the App Store version. Updates, reinstalls and switching between the two no longer ask for your password for them. Secrets saved before this update stay where they are and are still read from there (#1162).
- **Smart Mode settings read in order:** the target language now sits directly under the preset it belongs to, and options that only apply to one choice (target language, OpenAI key, model) are indented under it. Rows are separated by one line each and the spacing is the same throughout. Works the same on macOS, Windows and Linux (#995).
- **Recordings stay on this Windows computer and private to your account:** kept recordings, parked dictations and import copies now live in %LOCALAPPDATA%\WhisPaste instead of the roaming profile folder, so they are never copied to other computers with a roaming account. Existing files move there once at the next start. The folders are restricted to your Windows user account; other user accounts on the computer cannot open them without administrator rights (#265).
- **Same list keys everywhere:** J and K now move the cursor in Notes, Snippets and Replacements too, as they already did in Recordings (not in a text field, not with a modifier). F marks a favourite only without Cmd or Ctrl, so Cmd/Ctrl+F always jumps to the search. Works the same on macOS, Windows and Linux.
- **Clearer highlight when a link opens a setting:** the setting a link points to now also gets a narrow accent bar at its start edge, easy to see in every colour set; the soft tint stays.
- **A withdrawn Input Monitoring permission no longer leaves a single-key hotkey silently dead:** if macOS takes the permission away while a single key (such as right Control or Fn) is your dictation key, your key combination takes over at once and a notice explains why, with a button to the system settings. On Linux (X11) a stopped single-key watch is also noticed every 15 seconds and rebuilt a few times before the combination takes over. Detecting a stopped watch on macOS and Windows follows in a later update.
- **The Dictionary explains each thing once:** three short sentences under the tabs say what Terms and Replacements are for; the repeated hint bands and intro texts are gone. An empty term list says how to start and offers terms for your work, a search without a hit offers to add it as a term, the Suggestions tab shows how many are open, and the engine hint only appears when the active speech recognition takes no terms (with a button to create a replacement instead). Settings search opens the matching tab, and "Terms" is the one name everywhere.
- **Linux: withdrawing the Auto-Paste permission is clearer and takes effect at once:** the .deb package now installs the `acl` tool it needs to cut the session's access immediately. The button, its message and the handbook now use one verb per language for withdrawing the permission ("Withdraw permission" in English). The handbook also notes that access stays if another rule on your system (for example from Steam) grants it too.
- **Dictation with automatic language needs one analysis pass less:** the speech model no longer analyses the same audio twice when it detects the language itself. On a Mac this made a 15-second dictation about 0.3 seconds faster. Text and language stay the same. Same on macOS, Windows and Linux.
- **Dictation messages appear on the overlay card:** while you dictate in another app, paste, model, GPU and recovery messages show on the overlay card instead of a toast, because the main window is usually hidden. An error stays until you close it; a hint closes itself after at least 8 seconds. With the overlay off, the same message appears as a banner in the main window. The CPU fallback also stays visible in the speech recognition settings. Works on macOS, Windows and Linux.
- **Language, profile and short-press hints appear at the overlay:** switching the dictation language with the hotkey or the profile in the tray is confirmed briefly at the pill instead of a toast. Cycling quickly through languages shows only the last one. A hint raised during a recording appears after it. "No favorite languages yet" and the short-press hint (turn on "Tap or hold") are overlay cards with a button. With the overlay off, they appear in the main window. Works on macOS, Windows and Linux.
- **Dictionary, Replacements and Snippets keep their messages on the page:** errors and import or export results stay in a notice under the page header until you close it, instead of a toast that disappears. Screen readers read them out.
- **Undo and app-wide hints sit in a bar at the bottom of the window:** "Undo" after deleting, archiving or a Smart Mode edit, and hints without a fixed place (start-up, a hotkey that stopped working, a link that did not open) now appear in a bar at the bottom of the window instead of a toast. The bar never covers buttons, Undo stays at least ten seconds, waits while the pointer or focus is on it and also works with Ctrl+Z (Cmd+Z on Mac) outside text fields. Errors stay until you close them and say what to do next. Screen readers announce every message.
- **Settings errors stay on the screen:** a setting that could not be saved, a failed automatic backup and a link that did not open now show a notice under the page header until you close it, instead of a toast that disappears. A later successful backup clears its notice. Screen readers read them out.
- **No more beta updates:** the "Beta Updates" switch under Settings → Updates is gone. WhisPaste now offers stable releases only, on macOS, Windows and Linux. If you had beta updates switched on, the setting is dropped quietly on the next start and nothing else changes: your settings, recordings and notes stay as they are.
- **The beta update feed is gone:** versions that still have "Beta Updates" switched on no longer receive updates. Open Settings → Updates in that version and switch to Stable. If that version is newer than the latest stable release, it cannot step back on its own: install the current version once from the download page.
- **Every settings switch says what it does:** a screen reader now names the setting when a switch gets focus, not just "on" or "off".
- **Clearer for keyboard and screen readers:** the segmented switches (for example the period filter) show a clear accent ring when they get keyboard focus, and keyboard focus rings in the default colour are now clearly visible in the light colour set, and icon-only segments and icon buttons are announced once instead of twice. In the learning log, "Remove from log" names the correction it removes, and the log no longer says it is empty while it is still loading. On the support page, a screen reader announces the confirmation after "I already support WhisPaste". Text links now start exactly on the text edge of their column.
- **How WhisPaste learns, without a mouse:** the info icon next to "Learn from corrections" in the Suggestions tab is now a button that opens the explanation inside the card. Keyboard, touch and screen readers reach it; before, it was a tooltip for mouse users only.
- **Recordings answer on the page:** messages on the Recordings page no longer pop up and vanish. Errors stay next to the recording or at the top of the page until you close them and say what to do next, the storage error keeps "Copy diagnostics", and an export names where the file went. Refused dropped files stay visible too. Confirmations that only repeated what the list already shows are gone. Failed tag deletes, title changes and emptying the trash now report an error instead of failing silently. Works on macOS, Windows and Linux.
- **Clearer hotkey settings:** one "Hotkey behavior" choice (press to start and stop, hold, or tap or hold) replaces two switches, and the hold threshold moved under Advanced at the end of the page, so the dictation card stays short at large text sizes.
- **Notes answer at the editor:** messages in Notes no longer pop up and vanish. A refused image, a missing selection, a failed export or a voice error stays at the top of the note until you close it and says what to do next. The export names where the file went, "Snippet created" is confirmed at the editor, and confirmations that only repeated what you can already see (saved version, restored version) are gone. Works on macOS, Windows and Linux.
- **Settings, paste check and statistics answer in place:** messages in Settings, in the paste card and on the Statistics page no longer pop up and vanish. A failed reset, a failed export or import, a refused permission or a failed statistics reset stays at its section until you close it and says what to do next; export and import name the file's location; an incomplete factory reset opens a dialog that names what is left and offers to try again. Confirmations that only repeated what you can already see (statistics emptied, model ready, access removed) are gone. Works on macOS, Windows and Linux.
- **Linux says what it cannot do:** the update setting now tells you that updates are installed by hand from the release page, and the empty clipboard tab of the side panel and the manual explain that WhisPaste reads the clipboard only when you open the panel.
- **Dock: "Thanks" in the row, microphone in "More":** the sponsor or thanks chip now sits in the dock row and moves into "More" only when the window is narrow. The microphone choice moved into "More" as a submenu that names the current device. Same on macOS, Windows and Linux.
- **Right-click menu of the floating button matches the tray menu:** the same groups, names, separators and shortcuts as the tray menu, with the current microphone, language and mode ticked in the submenus. The menu follows the app's light or dark look and does not take focus from the app you dictate into. The overlay's right-click menu shows its Cancel key and ticks the current overlay size.
- **Setup: the last page shows what happens with the text after a dictation:** whoever skipped the access page or only pressed "Next" there now sees "Copy to clipboard" before starting, with a "Change" link back to the access page where Auto-Paste is set up. Nothing changes about the default.
- **Linux: the AppImage shows up in the application menu:** on its first start the AppImage adds an entry with its icon to the application menu, and keeps it current when you move the file. The system settings can then open WhisPaste's own page, where GNOME on Wayland lists its keyboard shortcut; before, they only showed the list of apps. Once you install WhisPaste as a package, the AppImage's entry gives way to the package's.
- **Onboarding buttons always in reach:** on every onboarding page the main button (Next, Allow, Continue and the like) and the skip links stay pinned at the bottom of the page at any window size and text size; only the text and choices above them scroll. On a small window or with large text you no longer have to scroll to find the button.
- **One kind of text link:** every text link in the app looks and reacts the same: accent colour, underlined on hover, a light wash while pressed, an arrow when it opens another place in the app and the external-link mark when it opens a web page. Links that were drawn as buttons (privacy policy, imprint, report an issue, the ideas board, "Other speech model") are now links like the rest, and screen readers announce them as links with their full name.
- **Sortable Replacements and Snippets:** a sort button above each list orders Replacements by trigger, result, date added or date changed, and Snippets by title, date added or date changed, each in either direction. The choice is remembered; the default is A–Z (by first trigger, or by title). A new or changed entry scrolls into its place and is highlighted briefly. The display order never changes the order in which replacements run. Existing entries keep their creation date when edited, and the date changed starts with the next edit.
- **New replacements start as "Similar", tolerance "Strict":** a new entry also catches small recognition errors, such as "Whis Paste" for "WhisPaste", when every trigger has at least 4 characters and contains a letter or digit; otherwise it starts as "Exact". This applies to the dialog, examples, symbol templates, learned corrections, the vocabulary import and CSV rows without a mode. Existing entries keep their mode. A similar match no longer takes another form of the same word: "project" no longer rewrites "projects", and this also holds for existing similar entries. Punctuation next to a similar match stays, so the period after a replaced word at the end of a sentence is no longer lost.
- **Usage statistics:** the `DNT=1` environment variable no longer switches usage statistics off. The switch in Settings is the only off switch; the operating system's Do-Not-Track signal was already ignored.
- **Contact address:** every WhisPaste address, in the app, the website, the privacy notice and the handbook, is now kontakt@whispaste.de (contact@ is retired).
- **Search puts title matches first:** searching Snippets, the snippet picker and Replacements now ranks a match in the title (or trigger) above a match only in the text, a whole word above part of a word, and finds all typed words in any order. Small typos in longer words still find the entry, behind exact matches. Case, accents and ß/ss do not matter.
- **Safer automatic updates on macOS:** the bundled Sparkle moves from 2.9.4 to 2.10.1, now embedded from a pinned, checksum-verified download. This brings Sparkle's security fixes: an update package whose signature check failed is now rejected, and applying an update is hardened against symbolic-link tricks when patching files and moving the downloaded archive.
- **Parakeet CPU engine updated:** the bundled sherpa-onnx moves from 1.13.4 to 2.0.1 and ONNX Runtime from 1.27.0 to 1.28.2. The installed Parakeet model keeps working without a new download. Very quiet recordings are now recognised: with six German test sentences turned down by 50 dB, the word error rate fell from about 30 % to 5 %, and at 60 dB below normal level, where the old version returned no text at all, from 100 % to 3 % (measured on macOS and Linux). At normal level the result is unchanged. A damaged Parakeet model file is reported as a load error and the app keeps running.
- **Onboarding statistics in one place:** with "Help make WhisPaste better" on, the onboarding reports which page was shown, left, skipped or gone back from, how long it stayed open as a rough bucket, and fixed outcomes such as the permission results, the hotkey test, the model download and the first dictation. Everything waits until you finish the onboarding and is dropped if the switch is off. Reviews and the run after an update are counted apart. Never your keys, names, text or audio.
- **Onboarding is clearer at a glance:** the hotkey page shows a highlighted "Now press and hold …" pill while it waits for the key, also after you pick another key. When the speech-model download moves from the first page to the top of the following pages, its status pill slides in and rings three times so you notice where it went. The closing page shows the WhisPaste wave mark large in its painting. With reduced motion nothing moves.
- **Trying out waits for the speech model:** while the speech model still downloads, the onboarding's try-out page says so and shows the progress instead of inviting a first dictation; it opens by itself once the model is ready. A failed or missing download offers Retry or Load right there. Pressing the hotkey meanwhile records nothing and shows no error, and no notifications pop up while the onboarding is open: the page answers itself.
- **Livelier waveform:** the waveform in the recording overlay and in the onboarding microphone test now follows one shared level curve. Normal speech moves the bars through the middle with clear peaks, a pause between syllables shows as a dip, and only loud speech reaches the top. Before, the overlay sat near full height while you spoke and the microphone test barely moved. The level is measured the same way on macOS, Windows and Linux.
- **Crash reports send crashes only:** the "Send crash reports" switch now sends crashes, hangs of 5 seconds or more and serious errors, nothing else. The small sample of performance timings and the session start/end records that rode along with it are gone. How WhisPaste is used is counted only by the separate "Help make WhisPaste better" switch. Both switches stay on by default and never send audio or text.
- **Onboarding in seven pages:** each page has one main action and a progress bar, and your first dictation lands in a practice chat in the window. Closing the window pauses setup; resume it from the tray. After an update, existing users see one hint that opens the microphone page as a check, and their settings stay unchanged. After the first practice dictation, the page shows how to speak longer: tap the hotkey twice quickly to dictate hands-free, one press ends it. Next waits on the microphone page until speech is heard and on the hotkey page for a confirmed conflict; without a speech model, the last page offers to load one.
- **Usage statistics record the speech model and hardware class:** the usage statistics ("Help make WhisPaste better" under Settings → Privacy) now also say which speech model and engine ran, with coarse classes for RAM, GPU vendor, Mac chip and compute backend. Device, GPU and chip model names are never sent.
- **Privacy policy updated:** the policy now describes the two data streams (usage statistics and crash reports) as they are sent, with their switches, retention times and legal basis. It is available in all eight website languages; the German text is binding.
- **New overlay look for new installs:** the recording overlay starts with the amber background, the ink wave, the compact size and a fixed outline. The fluid outline is off by default; turn it on under the overlay settings. Existing installs keep the look they have.
- **Side panel off for new installs:** the quick-paste side panel at the screen edge now starts switched off; turn on "Clipboard Quick-Paste panel" in Settings › Appearance. Existing installs keep the setting they had. During the first-run introduction it never appears.
- **Neutral wave retired:** the wave colour Neutral is removed, because it was practically the same as Ink. A saved Neutral becomes Ink. On a dark background, where Ink is not visible, the wave changes to Cyan.
- **Clipboard comes back only after proof:** after a paste, WhisPaste puts your previous clipboard content back only once the app has read the transcript from the clipboard. If the paste cannot be confirmed in time, the transcript stays on the clipboard. On macOS, WhisPaste does not try to paste while a password or PIN field has the keyboard; it leaves the transcript on the clipboard and says so. New installs use this behaviour. Installs that finished onboarding before keep the previous timed restore. Under "Clipboard after pasting", the new switch "Restore even without confirmation" turns that timed restore on or off.
- **Long recordings are cut at pauses:** a long recording is split for cloud and local speech recognition where nobody is speaking, not at a fixed length. Where a speech pause is missing, the next piece repeats 2 seconds of audio and the words heard twice at the join are removed. The end of each piece is passed on as context to the next one, so names and sentence style carry across the cut. A piece that the recogniser repeats in a loop passes nothing on, and words the recogniser copies from that context are removed.
- **OpenAI speech-to-text uses gpt-transcribe:** the OpenAI option now sends each recording to OpenAI's `gpt-transcribe` model instead of `whisper-1`. OpenAI retires `whisper-1` on 26 February 2027. The model is not a setting, so there is nothing to change: your key and the speech-recognition settings stay as they are. Long recordings still go up in slices of at most 24 MB.
- **Onboarding window and privacy page:** the onboarding window opens at 1100×800 on every platform (smaller screens cap it to the work area). The last page reads "Ready to dictate.", says where your audio goes in the chosen mode (stays on this device, or straight to the cloud provider or your own server) and holds two switches with the same wording as Settings → Privacy: "Help make WhisPaste better" (usage counts) and "Send crash reports", neither ever with your audio or text. Keeping recording audio is no longer asked during setup; the page points to Settings → Privacy and links the privacy policy. The contact button breathes three times when it appears and then rests. The hotkey page keeps its recommendation and the button that applies it in view at every text size.
- **Flat dialogs:** dialogs dim the window behind them without a blur.
- **One button row in every dialog:** all dialogs share the same footer: Cancel and the main action sit side by side at equal width, larger choices stack. Enter confirms the main action only while no other button has focus, so Enter on a focused button runs that button. A click outside a dialog closes it, except while a form holds unsaved input (it asks first) or an operation is running.
- **Speech model:** WhisPaste recommends a model from this computer's hardware class and its own measurements, and the model stays loaded between dictations by default so the next hotkey press starts at once.
- **Settings in areas:** settings are split into areas with a navigation column, and search jumps to the matching area in all six interface languages.
- **Auto-paste and clipboard:** an app picker replaces the text list of apps that skip auto-paste, and a setting restores your previous clipboard after each paste.
- **Overlay:** new shapes, wave styles and colour presets, a recording ring, adjustable size and opacity, and a position that is remembered per monitor.
- **Recording controls:** double-tap the hotkey to record hands-free, choose a separate cancel key, and let a microphone priority list take over when a device is missing.
- **Statistics:** shows raw versus revised words, transform actions and frequent corrections, and labels the time saved as an estimate.
- **Onboarding:** Enter and Escape move through the setup, a model download can be cancelled, and a download the disk cannot hold is refused before it starts.
- **Replacements use the page:** the explanation cards are gone, so search and Add stay fixed while the list scrolls. Import, export and the try-it test sit in the "more" menu; while replacements are off, a banner offers to turn them on.
- **GPU memory check:** a speech model larger than the detected graphics memory loads on the CPU, and the speech settings say why.
- **GPU details in crash reports:** crash reports carry the GPU name, its memory, the backend and, on Windows, the driver version.
- **Swatch rows announce their choice:** each colour row is announced as a radio group with one checked swatch.
- **Snippets straight from the trigger word:** say the trigger word followed by a snippet's name (for example "signature") and WhisPaste inserts that snippet directly, without the picker. If the name matches several snippets or none, the picker opens with the name already in its search field. Saying the trigger word alone still opens the picker as before.
- **Interactive snippets in one sentence:** in the snippet picker, press Cmd+Enter (Ctrl+Enter on Windows and Linux) or click "In one sentence" on an interactive snippet and say all fields at once, for example "Cancellation to Ms Krüger, appointment Tuesday". A preview shows the recognized values; fix any of them, then Enter inserts and Escape cancels. Field names you say along are always recognized; with the Smart Mode text model ready, a natural sentence is mapped too, and only words you actually said are used. The guided field-by-field recording stays as it is.
- **Snippet picker trigger in Settings:** the spoken trigger word is set in Settings under Shortcuts, next to the picker hotkey. The Snippets page links there instead of holding the field.
- **Feedback mood ratings use icons:** the five ratings are drawn icons instead of emoji, so they look the same on every system.
- **Multi-select bar in History:** Delete and Cancel stay on the bar at every text size. Merge, copy, export, restore and archive moved into a "More actions" menu, and the destructive label wraps instead of pushing Cancel out of view.
- **Linux and onboarding wording is accurate:** the Linux speech-to-text page no longer promises dictation into every app, since auto-paste needs a one-time uinput setup and Wayland limits hotkeys and paste. The onboarding model step says the voice stays on your device with local recognition, because the step can also lead to a cloud engine.
- **Website and app copy no longer promise dictation into every app:** the website, the SEO descriptions, the AI-facing `llms.txt` and the app's shortcut and paste-blocklist texts now say "in almost any app" or "in most text fields", since Linux under Wayland limits global hotkeys and paste.
- **Text replacements are on from the start:** new installations apply your replacement rules to every dictation. Existing installations keep text replacements off, as before, unless you switch them on; a choice you have saved is never changed.
- **Page notices polished:** closing a notice returns the keyboard focus to where it was; at a large system text size the notice button moves below the message; the Statistics notice stands under the page head and the Snippets notice stays above the scrolling list; a CSV import that adds nothing now says so.

### Fixes

- **WhisPaste never runs twice on the same data, even when its start lock cannot be created (#1647):** before, WhisPaste started normally when missing rights kept it from creating its start lock, so a second copy could write to the same data. It now also checks a second lock in your temporary folder and starts normally whenever one of the two works. Only if neither can be created does it show a start screen that explains this in plain words and lets you quit or open WhisPaste anyway; your data stays closed until you answer. `whispaste --transcribe-file` with `--replacements` now only reads your dictionary, so it can run next to an open WhisPaste without changing its data. Works the same on macOS, Windows and Linux.
- **Long dictations on slower computers are no longer cut off, and a stuck transcription frees the speech model (#1639, #1619):** local speech recognition (Whisper and Parakeet) now gets a time limit that fits the speed measured on your computer, and it extends the limit while the transcription keeps making progress. Before, a computer without a fast graphics card could hit a fixed limit on a long recording and lose it. If the limit does run out, WhisPaste stops the transcription, keeps the recording under failed recordings so you can try again with more time, and your next dictation starts at once. A Parakeet recording that ran out of time is now kept as well instead of being deleted. Cloud services keep their previous limit. Same on macOS, Windows and Linux.
- **Long recordings need much less memory while they are transcribed (#1642):** a 60-minute recording no longer turns into one large block of audio data for local Whisper. WhisPaste now prepares the audio piece by piece for each section it transcribes, and the automatic volume levelling reads and writes the file in small steps. Measured on a Mac with a 60-minute recording: about 225 MB less extra memory during transcription (503 → 277 MB) and about 105 MB less during levelling (128 → 25 MB); the transcript is the same. Works the same on macOS, Windows and Linux.
- **Local speech recognition keeps a long recording in memory only once (#1665):** Whisper and Parakeet now read the recording from its file piece by piece instead of getting their own copy of it, and Parakeet no longer converts the whole recording at once. Measured on a Mac with a 60-minute recording: Whisper needs about 105 MB less extra memory (275 → 170 MB) with the same transcript, and handing the recording to Parakeet about 865 MB less (1,070 → 205 MB). Works the same on macOS, Windows and Linux.
- **Speech model downloads are sturdier:** the Parakeet download in 1.4.2 could fail with "Downloaded file size mismatch" after the model's publisher changed its files. Every model now comes from a fixed, unchangeable version and is checked against its known checksum. A download that hangs or meets a busy server ("too many requests") picks up where it stopped instead of quietly ending. A download interrupted when you close WhisPaste continues from there at the next start, for up to a week. Two WhisPaste windows no longer download the same file at the same time. The handbook now explains how to install the Parakeet files by hand, and Parakeet files put into a folder ending in "-int8" are found and taken over. Same on macOS, Windows and Linux.
- **Clear words when a model download or delete fails in Settings (#1633):** Settings no longer shows technical texts such as "Download failed: HTTP 503" or a German network message in any language. Speech, Parakeet and Smart Mode models now say in your language what went wrong (no connection, server problem, damaged file, not enough space) and a failed delete says so and what to do.
- **Hebrew layout mirrors correctly (#1634):** in Hebrew, the highlight of switches such as "This week / All time" and the side panel tabs now sits under the chosen option instead of the mirrored one. The list of recordings, notes and snippets stays on the start side with the detail next to it, and dragging the divider moves it the way you drag.
- **Plain wording and visible load errors (#1635):** fields and hints that asked for a "bundle ID" now ask for the app identifier (for example com.apple.mail). When the notes of a recording or the overview figures cannot be loaded, a message says so and offers "Try again", instead of an empty space or zeros; the term list in the Dictionary shows even while settings are unavailable. The diagnostics preview and copy no longer spin forever: after 10 seconds they show the short fallback report. "Reduce motion" now also stops the arrow in onboarding choice fields and the scrolling of lists and tab rows.
- **Clear notice when a password prompt blocks auto-paste (macOS, #1617):** when a macOS password window (administrator password, keychain, Touch ID or the lock screen) or another app protects the keyboard, the notice now says so in plain words: "Not pasted automatically", what is open, what to do and that the text is on the clipboard (⌘V). It no longer tells you to quit "SecurityAgent", which is that password window. The overlay card shows the whole message instead of cutting it off after three lines. Terminal and iTerm2 still name their "Secure Keyboard Entry" switch; the hotkey notice uses the same wording.
- **"Open settings" lands on the setting the message names (#1616):** the button on a missing or invalid cloud key now opens the key field of the service you use, and the message names that place (API keys for OpenAI and Deepgram, Speech recognition for your own server). The GPU messages open the graphics card setting, a speech model that cannot start opens the speech model choice instead of the reset button, and the no-favorites hint for the language shortcut opens the favorites. Each jump scrolls to the setting and marks it, also when the window was hidden, Settings was open on another area or a search had no results. A setting your current choice hides leads to the choice that shows it. Same on macOS, Windows and Linux.
- **Linux AppImage finds the microphone on a fresh Ubuntu 26.04 (#1608):** the AppImage now brings its own recording and microphone-list tools (`parecord` and `pactl` from PulseAudio), so it lists your microphone and records without installing `pulseaudio-utils` first. They work with PipeWire and PulseAudio, and are used only by WhisPaste; tools installed on the system stay untouched. The `.deb` already installs them as a dependency.
- **"Another app slows the keyboard" says what to do and stays closed (macOS, #1607):** the notice now has a "What to do?" button that opens the matching help steps, including how to switch off the Siri keyboard shortcut. Once you close the notice, it does not come back for that app, also not after a restart. The quiet hint in the hotkey settings stays.
- **WhisPaste stays responsive under heavy load on the Mac (#1451):** when macOS reports memory pressure, an idle speech model is now released before the system runs out of swap and pauses the app. Before, the app only reacted at under 10 % free memory and could freeze during parallel builds. The model loads again once the pressure is gone; a running dictation is never interrupted.
- **Double tap on a single key stays on (Windows, #1469):** the check that watches the single-key trigger wrongly read a working key as lost, rebuilt it three times and then switched to the stored key combination, so the double tap stopped working about a minute after the start. The check now reads the system's answer correctly and the double tap keeps working.
- **No more crash when pasting a dictation on macOS (#1484):** WhisPaste could quit suddenly right after a transcription, or after inserting a snippet, when clipboard history was reading the clipboard at the same moment. Reading and writing the clipboard now take turns; a slow app that holds the clipboard still cannot freeze WhisPaste.
- **Data access screen in your language (#1461):** when the system asks once for access to your encrypted data, for example after an update, the screen now appears in the language you last used (or the system language) instead of English. It calmly says that your data is protected on this device, why the system asks and that nothing is lost, and lets you change the language right there; that choice stays after unlocking. Also on macOS, "Allow access" now really asks: the entries of the old keychain are read one by one, so the system dialog appears and the app starts normally afterwards; a technical failure is no longer reported as "not allowed".
- **Selection bar readable at large text (#1388):** in History and Snippets, the bar shown while several items are selected keeps the count, "Select all" and "Delete" whole at narrow windows and large text sizes, also in right-to-left languages. What does not fit moves into the "More" menu instead of wrapping mid-word, and stays reachable by keyboard and screen reader.
- **Pill hints are read out once (#633):** when you switch the profile or the dictation language, a screen reader now announces the short confirmation at the overlay pill once instead of twice.

- **Clean overlay when a new recording starts over a card (#1193):** starting a dictation while an error or notice card is still shown no longer leaves the overlay too small for its content for a moment, so nothing overflows or overlaps. The window size and its content now change in a fixed order, and a card that does not yet fit is trimmed instead of spilling over. Same on macOS, Windows and Linux.
- **Overlay notice cards match what the app is doing (#1195):** while nothing is recording, a card no longer offers "stop and paste"; key hints name the trigger you set (a single key or your shortcut), and the "still busy" card closes as soon as WhisPaste is ready again.
- **macOS: no keychain prompt at start (#1161):** WhisPaste no longer reads the keychain at start in a way that can make macOS ask for access, for example after switching between the App Store and the direct download. Saved keys and tokens that would need such a prompt wait until you allow access after the data-key explanation (or under Settings › Privacy) and are read then. Windows and Linux never showed such prompts at start and behave as before.
- **No false "not confirmed" warning after a paste that arrived, and honest wording when it does appear (#1147):** a paste whose read confirmation arrives a little late (up to one second after the wait) now counts as delivered. If the paste really cannot be confirmed and "Restore clipboard even without confirmation" put your previous clipboard back, the message no longer claims the text is on the clipboard; it says so and offers "Paste again". The warning after the snippet picker, the side panel or a re-paste no longer offers "dictate again", because nothing was dictated there. The log now records, for every unconfirmed paste, whether and when the text was read and which app was the target.
- **Keyboard shortcuts page at large text sizes:** at text size 2.0 the "Hotkey behavior" choice and the hint in the snippet picker trigger field are no longer cut off; both widen to show their full text in every language. Same on macOS, Windows and Linux (#1018).
- **Support page: the coffee block no longer jumps:** Ko-fi and Buy Me a Coffee stand in their final place from the first frame; the tiles around them no longer shift while the page loads. Same on macOS, Windows and Linux (#1003).
- **Replacements with special characters match correctly, and the longest trigger wins:** triggers that start or end with a symbol, such as "C++", ".NET" or "@handle", are now found as whole words, and when several replacements could apply to the same spot, the longest trigger is used. Replacements still build on each other in the order you created them. Works the same on macOS, Windows and Linux.
- **Setup uses a speech model that is already installed:** when a speech model from the catalog is already on disk (for example after a reinstall), the start page of the first-run setup preselects it, and "Set up" downloads nothing. Without an installed model, the recommended model still downloads in the background after you agree on the start page. Works the same on macOS, Windows and Linux.
- **The floating button no longer goes blank after a restart of its renderer:** when the button's renderer is restarted because it stopped drawing, the new one starts with the last look, size and state, so the stop sign stays visible during a recording. If the restarts are used up, the button recovers with the next recording instead of after an app restart (#977).

- Notes now show a recovery hint when creation fails, preserve the current list, and log SQLite result codes without private database details (#917).

- **A down cloud speech service no longer stalls every dictation:** after three failed requests in a row (network, timeout, server error, rate limit) to the same service, new dictations to it fail at once instead of running the whole retry chain, and the recording stays kept for a new try. After one minute a single probe request checks the service; success lifts the pause, failure doubles it up to ten minutes. A wrong key, used-up quota, rejected request or wrong answer format of your own endpoint never triggers it, and a new key or provider starts fresh. Nothing is stored across app starts. Deepgram now also retries server errors and rate limits like OpenAI. Same on macOS, Windows and Linux.
- **Closing a notice never starts a recording:** a click on the close cross of a notice over the dictation pill (for example after text could not be pasted) now always closes it like Escape. Before, a click that just missed the cross reached the pill and started a new recording. A recording started by a click on the pill is now named in the log. Same on macOS, Windows and Linux.
- **Mini overlay no longer runs the live preview while recording:** in the Mini size the overlay shows text only while transcribing, so the live preview no longer decodes audio during the recording. The text while transcribing stays as before. Same on macOS, Windows and Linux.
- **The slow-keyboard notice no longer repeats (macOS):** when another app (for example a window manager) checks every key press slowly, WhisPaste named it again every 30 minutes on the first recording, although no press was lost. Now each such app is announced once, also across restarts, and again only when macOS switched a keyboard observer off since, or the delay got at least twice as long. The app stays visible in a quiet hint in the hotkey settings and in the hotkey step of the setup, with what to do. The log records the measured delay and the app name for every reading. Secure keyboard input is handled as before. Windows and Linux have no such signal, so nothing changes there.
- **macOS permission helper opens System Settings reliably:** the "Open System Settings" button no longer does nothing when the system's accessibility prompt process is still running without a visible window; it now only defers to that prompt while its window is on screen.
- **Model downloads no longer fail with "size mismatch" after a resumed transfer:** a download whose length did not match the expected size (for example a resume answered with the whole file or a different byte range) was put in place anyway and then rejected, throwing away the whole file each time. Now a body that ends short is resumed, one that is too long or a resume that starts at the wrong byte restarts once from the beginning, a partial file that is already complete is used without downloading again, and a second download of the same model started meanwhile (a repeated click, or another screen) reuses the finished file instead of writing into it or replacing it. The size error appears only if a fresh download still has the wrong length. Works the same on macOS, Windows and Linux.
- **A wrong Parakeet file is downloaded again instead of failing (#1546):** a Parakeet file counts as installed only with its exact expected size. A file of the right name from another source, or a cut-off copy, is now replaced by the download instead of making the speech engine fail when it loads.
- **Hiding "Get involved" stops every project-numbers request:** with the "Get involved" section hidden on the overview, the support page no longer asks api.whispaste.de for the GitHub star count either. One switch, no request.
- **Factory reset also removes a left-over old history folder (Windows):** an installation that still had its history in the old double-nested `WhisPaste\WhisPaste` folder could keep a plaintext copy there after "Delete all data", for example when moving it to the current folder had failed. The reset now removes that folder, including its database and sidecar files.
- **Closed MacBook no longer records silence:** with the lid shut, WhisPaste no longer switches to the built-in microphone (it has no signal then) and does not suggest it. If the built-in microphone stayed silent, the next recording uses another working input and a note names it. The log now records the silent device, the candidates, the suggestion, your choice and the lid state, empty log backups are removed instead of left behind, and the log no longer prints "OVER BUDGET" for the hotkey-to-overlay time. Windows and Linux behave as before.
- **"Record {n} more min" keeps recording instead of stopping:** the time-limit card counts on a different clock than the recorder, so a click close to the limit could land after the recorder had already stopped. The recording now runs up to 3 seconds past the limit while the card is still on offer, the card stays at 0:00 meanwhile, and the click only ever extends the limit once. The pill confirms it with "Recording extended by {n} min". Works the same on macOS, Windows and Linux.
- **Shortcut hints match the platform in the history detail:** the tooltips of the transcript edit bar and the history shortcut help name Cmd (⌘) on macOS and Ctrl on Windows and Linux, the keys the shortcuts actually listen to. Before, they always named Ctrl, so on a Mac a hint could point to a key that did nothing.
- **Auto-paste works on keyboard layouts that move the shortcut keys (macOS):** the paste and copy keys are now looked up with Command held, so "Dvorak - QWERTY ⌘" no longer sends Command+K and non-Latin layouts such as Russian keep working; plain Dvorak was already handled.
- **A lost hotkey release ends the recording:** on Windows, on Linux (X11) and on macOS, recording with a held hotkey could run on when the release did not reach WhisPaste, for example after a screen lock or a switch of user. WhisPaste now checks the real key state while the hotkey is held and ends the recording within about a second, as if you had let go. On macOS this check needs the Input Monitoring permission; without it, and on Wayland, the release event stays the only signal, as before.
- **Cards during a recording say what their buttons do, and Esc no longer throws a dictation away unasked:** the time-limit card now offers "Record {n} more min" and "Finish and paste", the quiet-microphone card leads with "Finish and paste" and offers "Choose microphone" second, and the cross on these cards reads "Hide hint": it hides the card for the rest of the recording and keeps recording. After a disconnected microphone one button pastes what you said, and a follow-up card then offers the microphone choice. While a card is open, Esc first asks "Discard recording? Press Esc again" on the card, even for a short recording. Same on macOS, Windows and Linux.
- **No project numbers request on the first start:** the live GitHub and YouTube numbers of the "Get involved" block on the Overview are now asked for only once the block is really on screen, no longer while the onboarding still covers the Overview or while the window is hidden (for example after a start at login). This matches what NETWORK.md promises: never at start-up.
- **Tags survive an interrupted upgrade:** if WhisPaste was closed or hit a disk error while it moved old tags to the new tag list, the next start could skip the rest and leave some entries without their tags. The move is now all or nothing: an interrupted run is undone and runs again at the next start.
- **No false "could not paste" message:** on macOS, when the target app read the dictated text, the paste counts as done even if the system reported a missing permission or a failed key press; in that case the dictation stays on the clipboard instead of the previous content.
- **No grey rectangle behind the glass overlay on Windows:** the Windows acrylic backdrop only blurs in an active window, and the overlay never takes focus, so it showed a flat grey box around the pill and the notice card. On Windows the glass look now uses its opaque body, the same one "reduce transparency" shows, with the rounded shape of the pill and the notice card and nothing around them (#518).
- **Snippets are written through the single database writer:** creating, changing, deleting and replacing snippets now queue behind other history writes like every other change, so none can collide with a concurrent save. The Russian empty-trash hint reads "удалённые".
- **Hotkeys keep working after a settings import:** importing settings that change the colour set rebuilt the main window's services, and afterwards the UI-stall self-heal stayed off and Escape could no longer cancel a dictation that was running. The rebuilt window now takes over every hotkey, and an error inside a hotkey action is logged without ending the key handling. Errors in the window and in the background now always reach the local log, also with crash reports off, and a burst of them is shortened. Same on macOS, Windows and Linux.
- **Dictation history and logs are readable by you only (Linux, macOS):** the app-data folder is set to owner-only and its files (history database, logs, install ID) to owner read/write, at every start. Before, they kept the default permissions of your system.
- **Linux: taking Auto-Paste access back works at once:** after you remove the permission (button in the settings, or the command), WhisPaste stops typing into other windows right away and only copies the text, without a restart. If ydotool is installed and you are in the group "input", access stays through its rule.
- **Old full texts removed from the correction learning data:** earlier versions stored complete texts before and after a correction, and nothing used them any more. They are now deleted once when the app starts; your word corrections stay. Older backups or snapshots of your data folder may still contain them.
- **macOS: no more one-second freezes when overlay settings change while it is hidden:** Changing the overlay size, importing settings or switching between a notice card and the pill while the overlay was hidden blocked the whole app for about a second. A hidden overlay now resizes at once.
- **Glass overlay follows its content:** with the "Glass" background the pill is as wide as its content in every state (the notice card keeps the full window width), like the other backgrounds, instead of staying at full width with the narrower pill drawn inside it. The extra inner frame on macOS 26 and later is gone. Works on macOS and Windows (Linux was never affected).
- **Floating button and overlay should stay on screen on macOS:** both could disappear while you worked in another app, for example during a dictation. The two panels no longer hide when WhisPaste is not the active app, which is the suspected cause; please report it if they still vanish.
- **No more "iiiiiiii" instead of your text:** when speech recognition got stuck on one letter, that run was pasted and carried over into the next dictations. It is now dropped, and the next dictation starts clean.
- **Text and icons no longer break apart on macOS:** while a transcription kept the graphics chip busy, for example during onboarding, text and icons in the main window could turn into fragments and stay that way until restart. The macOS app now uses a different renderer that is not affected.
- **Snippet trigger word explained:** the Settings hint and the manual now say that the picker trigger word works only during a recording, and that WhisPaste never listens permanently. Texts updated in every app language.
- **Dictation works in the AppImage:** the AppImage could not find its speech recognition and sound libraries, so every dictation stopped with an error.
- **Linux: take the Auto-Paste permission back without the .deb:** in an AppImage, the tarball, a Flatpak or a Snap, the Auto-Paste card in Settings now shows the command that removes the virtual keyboard access again, with a copy button, for as long as the access is in place.

- **The slim idle capsule opens on hover on macOS:** with "Slim capsule when idle" on, the capsule did not open to the pill when the pointer moved over it. It now does, and it also opens by itself when the button falls back to the capsule while the pointer still rests on it. Under Linux with Wayland there is still no hover; the capsule stays narrow and a click starts recording.
- **Times stay whole in the Overview at large text sizes:** the time of a recent recording no longer breaks at its colon.
- **A failed paste stands out in the overlay:** when a finished dictation could not be pasted, the overlay now shows its error mark in the warning colour, like the dock, instead of a neutral mark that was easy to miss in the mini overlay.
- **Locked settings look locked:** a switch that cannot be changed no longer shows the accent colour, so it does not look active. Wave colours that are unavailable on the chosen background carry a lock.
- **The dock keeps what matters in narrow windows:** when space runs short, the dock now keeps the current Smart Mode and language visible as long as it can, then the hotkey on Dictate, and moves other controls into More first. The engine shows only its icon before the hotkey gives way. At large text sizes the hotkey is no longer cut off, and in right-to-left languages it reads in the right order.
- **A single key this system cannot use says so:** a settings import from a Mac with Fn as the trigger, or a single key on Wayland, showed a wrong reason on Windows and Linux, and the hotkey row named a key that was not listening. The row now shows the key combination that actually works, the notice says the key is not available on this system, and "Change" picks another trigger. The saved key stays for going back to the other system.
- **Frequent corrections show single words only:** the Analytics list "Frequent corrections" could show complete dictated texts from older versions, which recorded whole-text corrections. Those old entries no longer appear there.
- **Function keys work as hotkeys, and an unknown key is no longer blamed on another app:** a hotkey on F1 to F12 failed to register and was reported as taken by another app. F1 to F20 now work on macOS, Windows and Linux, also from an imported settings file. If a saved key can't be used at all, WhisPaste says so and asks for another combination instead of sending you looking for an app that doesn't exist. A profile with such a key no longer stops the other profile hotkeys from registering.
- **A recording stopped by the time limit can no longer paste later:** when a transcription hung for too long and WhisPaste gave up on it, a late result could still land in whatever app you had moved on to, and the next recording had to wait. Now a new recording starts right away. A late result is never pasted or copied; it goes to Recordings with a short notice, or is dropped when saving recordings is off.
- **Failed-recordings menu stays closed while audio retention is on:** with audio retention on, every keep period was disabled, so the menu opened and nothing could be picked. The setting is now muted; its row already says why it does not apply.
- **Retrying a kept recording that is gone says so:** "Try again" in the Recordings detail of a kept recording that was already deleted or processed did nothing. A message now says the recording is no longer kept.
- **Copying confirms where you clicked:** the copy button briefly turns into “Copied”, and a copy from a menu or shortcut answers at its row, with no toast in the corner. A failed copy shows at the same place and says what to do next. Screen readers announce both. Works on macOS, Windows and Linux.
- **No more toasts during setup:** while onboarding is open, no toast covers the page, whatever raises it. Messages the setup needs, such as a failed Linux input grant, appear as a notice on the page instead. Works on macOS, Windows and Linux.
- **Mac App Store: a calmer paste permission:** WhisPaste notices the switch without a restart where macOS allows it; otherwise it offers "Restart WhisPaste" as a second way once you are back, never while System Settings is in front. "Allow now" in the skip dialog asks for the missing permission instead of only closing. A fresh entry no longer gets the "Remove the old WhisPaste entry" dialog, a paste that did arrive no longer reports an error, and after the grant the last onboarding page has direct paste preselected.
- **Microphone notices end with the recording:** the overlay could still show "no signal" or "very quiet" after a recording ended until the next one started. Both now clear when the recording stops.
- **Audio import never stalls on a file added at the wrong moment:** a file added just as the previous import finished could stay queued without being imported. It is now picked up at once.
- **Onboarding names the working hotkey when yours is taken:** if another app holds the dictation hotkey you chose, the hotkey page of the onboarding now says which combination starts a recording until you pick a new one, in the same words as Settings. Works on macOS, Windows and Linux.
- **No connection is now its own message when a speech model download fails:** instead of a general download error, the message says there is no internet connection. On the setup page it also offers "Try again" and "Install speech model manually"; the second opens a handbook guide with the download addresses and the model folder for macOS, Windows and Linux. While the error is on screen there, WhisPaste checks every ten seconds whether the connection is back and then shows a hint; it never restarts the download without you. Starting WhisPaste without a network shows no dialog.
- **Menus show your real hotkey:** the menu bar menu and the floating button menu showed the stored key position (for example ⌘; instead of ⌘Ö on a German keyboard) and ignored a single-key trigger. They now show the same hotkey as Settings and the Overview.
- **Floating button keeps your colours while recording:** on macOS the button could turn blue with a light ring when a recording started, because its drawing restarted several times in a row and showed the default colours. A restarted button now waits for its colours before it draws, and one restart no longer triggers the next. The recording ring is now visible on every background, including amber and Gletscher.
- **Dictation recovers after a graphics card fault:** when the graphics driver reset during a transcription (on macOS this can happen system-wide), every later dictation failed until WhisPaste was restarted. WhisPaste now reloads the speech model once and, if that does not help, finishes the dictation on the processor. If that fails too, the recording is kept for a later retry and a message says what happened and what to do next.
- **Failed recordings are kept for 24 hours by default:** the audio of a dictation whose transcription failed is now kept for a retry for 24 hours instead of 7 days, the same on every path (right after the failure, after a crash, and in the retry list). "Keep failed recordings for" under Privacy still offers 1 to 30 days; a period you chose earlier stays as it is.
- **Tidier side panel:** the three tabs are now icons with a tooltip, so no label is cut off in any language, and use the same segmented control as the rest of the app. The section is called "Recordings" like in the sidebar instead of "Transcriptions". The preview of a long row appears as a styled tooltip inside the panel, below the row, instead of sticking out of the panel.
- **Cancelling a long recording from the overlay asks first:** the overlay's close button and "Cancel" in its right-click menu now ask before discarding a recording longer than 30 seconds, like the Escape key already did.
- **Correction suggestions no longer get lost:** a term is marked as accepted only once it is in your vocabulary, a suggestion that cannot be saved shows a message and stays in the list, two corrections saved in quick succession both count, and suggestions you have not seen again for 30 days are hidden.
- **No more frozen hotkeys and tray under heavy load (macOS):** when the Mac was short of memory, WhisPaste could stop answering its hotkeys and the menu bar icon for minutes. The memory and low-power checks looked up system functions anew each time on the main thread, and under memory pressure that lookup could stall. The functions are now looked up once, the checks run in the background with a time limit, and a check that does not answer is skipped. Windows gets the same protection; Linux was not affected by the lookup.
- **First-start language on Windows and Linux:** on a first start, WhisPaste now takes the app and dictation language from the system's preferred languages when the process reports no language (for example with the C or POSIX locale), instead of falling back to English. If the system names only languages Whisper does not write, the dictation language stays on automatic detection. Existing installs keep their settings.
- **Recovers from a frozen app:** when WhisPaste stops responding for about 20 seconds (dictation key and tray no longer react), it now restarts itself, at most once every 10 minutes, and says so calmly at the next start. Works the same on macOS, Windows and Linux; with crash reports on, one report goes out, never with audio or text. A dictation that was running is kept up to that point and turned into text after the restart.
- **Linux: "Start at login" works on KDE and other desktops, also when the install path has spaces:** the autostart entry now quotes the program path the way the desktop standard expects. Existing entries are rewritten on the next start.
- **Paste and microphone checks wait at most five seconds:** if the system does not answer a permission or paste check, WhisPaste keeps the last known status and does not pile further checks up behind the unanswered one.
- **Newsletter: a late answer no longer confirms the wrong sign-up:** if you signed up again, a delayed reply about the earlier sign-up could mark the new one as confirmed. Each reply now only counts for the sign-up it belongs to.
- **Linux: starts on newer and older distributions, sound feedback works there too:** WhisPaste now brings its own FLAC, Ogg, Opus and Vorbis libraries instead of relying on the version the system has. Before, a build could fail to start on Ubuntu 26.04, and the start/stop sounds stayed silent there.
- **Linux: a missing pulseaudio-utils is named instead of a vague error:** recording and the microphone list need this package. The .deb and Snap now bring it; for other installs the app, the microphone setting and the setup step name the package instead of saying no microphone was found.
- **Linux: the global hotkey works right after login with autostart:** the autostart entry is now named after the app (`de.whispaste.app.desktop`), so the desktop links the autostarted app to its shortcut. An existing entry is moved on the next start, and an AppImage that moved is updated.
- **Fields and buttons line up:** input fields, search fields, menus, buttons and icon buttons now share one height. A field and the button next to it, such as the newsletter address and "Sign up", end on the same edges at every text size; on the desktop the field used to be lower than its button.
- **Segmented switches keep the app font:** labels such as "This week / All time" in Russian or Hebrew fell back to a different font; they now use the app font and its fallbacks like the rest of the window.
- **A slow system no longer reads as a hotkey conflict:** when the system takes too long to answer a hotkey registration, for example while a Linux shortcut dialog is still open, settings and the onboarding hotkey page now say "The system hasn't answered yet. WhisPaste keeps trying." instead of claiming another app uses the key, and WhisPaste no longer switches to the fallback key. A hotkey change now waits until the previous one has ended (at most two minutes, see "Hotkey changes never stall"), so two quick changes can no longer leave the wrong key registered. A hotkey recorder that is left open gives the hotkeys back after two minutes instead of fifteen.
- **No "Tap or hold" hint after a real hold of a single key:** when a single modifier key (for example right Alt) is the dictation key, macOS, Windows and Linux now measure how long it was held from the key events themselves. A busy moment in the app can no longer make a deliberate hold look like a click and bring up the hint.
- **macOS permission helper stays out of the way:** the small panel that helps you drag WhisPaste into System Settings > Accessibility no longer covers the + and − buttons of the list. It opens below, beside or above the settings window, on that window's screen, and you can move it. It also says to remove an old WhisPaste entry with − first.
- **`--diagnose` always finishes:** `whispaste --diagnose --out <file>` on Windows wrote its report but sometimes never exited when started without a console. With `--out` the report now goes only to the file, and a console that cannot take it no longer holds up the exit.
- **Overlay and floating button restart when they stop drawing on Windows and Linux:** if the recording overlay or the floating button stops showing new frames, WhisPaste now restarts its drawing in place, at the same position and visibility, as it already did on macOS.
- **Live preview for quiet microphones:** the preview shown while dictating now uses the same idea of speech as the silence detection. A quiet microphone that dictation accepts also gets a preview; room tone and short clicks still start no preview update.
- **Images and files survive a dictation:** after pasting, WhisPaste now puts back everything you had copied before, not just plain text: images, files, rich text and HTML return in their original form on macOS, Windows and Linux. As before, nothing is put back when you copied something new in the meantime, and the restore stays out of clipboard history. Very large content (over 64 MB) or an app that answers too slowly falls back to restoring the text only.
- **Screen-reader announcements no longer pile up in memory on macOS:** each announcement (recording state, toasts, search results, recorded hotkeys) left a pending reply behind for the rest of the session, because macOS never answers it. They are now sent without waiting for a reply. The screen-reader messages of tooltips and other built-in controls are now sent the same way. Windows and Linux were not affected.
- **No double paste on Windows:** when the paste shortcut reports an error, WhisPaste no longer tries a second paste. On Windows that retry used the same clipboard and Ctrl+V path, so a partly delivered shortcut could insert the text twice. The text stays on the clipboard instead. macOS still retries once by typing the text directly.
- **Hotkey restores itself:** the global hotkey is registered again on its own after the computer wakes up, after the speech model was unloaded to free memory, after a long freeze of the window and every five minutes. It waits while you dictate, hold the key or record a new hotkey. A notice appears only after three failed attempts in a row. The manual's troubleshooting chapter explains it.
- **Quit always ends:** Quit, Cmd+Q, the tray's Quit and a termination signal end WhisPaste after at most 3 seconds, even if the orderly shutdown hangs. A normal quit is not affected.
- **Closing the window quits within seconds, so WhisPaste starts again:** when closing the window means quitting, and when you choose "Quit" while closing the first setup or a start screen, WhisPaste now ends after at most 3 seconds, like the tray's Quit. Before, a stuck shutdown could keep it running invisibly for up to half a minute, and starting it again seemed to do nothing. A second click while it closes changes nothing. Same on macOS, Windows and Linux.
- **Skipped auto-paste names the app in the way:** on macOS, another app can hold secure keyboard input (for example Terminal with "Secure Keyboard Entry" switched on, or a password field). Auto-Paste then does not paste, as before, and now says which app holds the input, how to get out (quit it or switch away; Terminal and iTerm2 get the menu switch as a tip), and that the text is on the clipboard for Cmd+V. Without a readable holder, the notice stays generic.
- **No stray letter after a hold-to-talk hotkey on Windows:** holding a character key as part of the dictation hotkey (for example AltGr+ö on a German layout) no longer types repeated characters into the window you dictate into. While the hotkey is held, WhisPaste swallows only the repeats of its main key and only once the modifier keys were released.
- **Double-tap notice names the reason per system:** Windows and Linux now say why a double tap is unavailable (Windows refuses to observe the key, Linux reports no key release) instead of the generic text. All six app languages.
- **Wayland hotkey note before saving:** the hotkey recorder and the dictation key dialog say that the desktop sets the shortcut, not WhisPaste, before you save a combination.
- **Linux conflict labels corrected:** Super+Space is the GNOME input source switch, Alt+F2 the run dialog on GNOME and KDE. An unverified KDE activity-overview entry is removed.
- **Fn conflict on the Mac:** the warning for the Fn double tap names turning off system dictation first, then choosing another combination.
- **Dock menu at large text sizes:** the Mehr menu and the dock dropdowns widen with the text size, and their labels wrap instead of being cut off with an ellipsis. Smart Mode, language and speech model stay reachable from Mehr at 2.0.
- **Many refused files no longer crowd the history:** when a drop or import contains files that cannot be imported, the history shows the first two reasons and a "Show all" button that lists the rest in a dialog, so the list keeps its room.
- **Fewer error reports, only the ones that matter:** WhisPaste sends crash and error reports only for crashes and real errors. The anonymous GPU vendor report, warnings such as the CPU fallback, and a speech model that is not downloaded yet are no longer sent. The same error is reported at most three times per session, at most 30 reports per session in total, and short stalls under 5 seconds are not reported.
- **Overlay window keeps a valid size on macOS:** a hidden floating overlay could collapse to zero size, and its render engine then logged an error on every frame, which filled the log file over days. The window now keeps a minimum size.
- **Recordings page keeps the search in view:** the search bar stays directly above the list while an import queue or interrupted recordings are shown. Both sit in one compact status line above the search bar: on a tall window the section opens inline with its first two rows and "Show all" for the rest, on a short window or at text scale 2.0 it opens a dialog with the full list. The header above the list no longer scrolls, and discarding a kept recording asks for confirmation first, in the same way as the recovery banner.
- **No background work after switching the overlay off:** if you turned the floating overlay off during a recording, its waveform animation kept running in the background until WhisPaste quit. It now stops when the recording ends.
- **Double tap falls back to the key combination:** where a double tap cannot be detected (Fn outside macOS, Wayland, or a Mac or PC whose keyboard does not report the key), the saved key combination takes over, so dictation keeps working. Settings and onboarding say so in one quiet line. Your double-tap choice stays saved and works again as soon as the device can detect it. A permission granted later in the system settings takes over when WhisPaste comes back to the front, without a restart.
- **Win key as dictation key keeps the start menu closed:** with the Win key as the double-tap key on Windows (verified on the left key; the right key uses the same code path), tapping it no longer opens the start menu as well. Win+E and other combinations work as before, and with any other dictation key the Win key opens the start menu as usual.
- **AltGr no longer counts as the right Ctrl key on Windows:** with the right Ctrl key as the double-tap key, typing AltGr characters such as @ no longer starts a dictation, and holding AltGr as the dictation key no longer stops the recording after half a second.
- **Right Win key returns to the start menu:** when Windows refuses to observe the right Win key as a double tap, the start-menu mask is released and the Win key opens the start menu again.
- **Hotkey changes never stall:** a hotkey change that has not finished within a minute is given up, and the global hotkey then shows as unavailable. The next change waits for it to end, or runs after two minutes at the latest, so one hung system call cannot block later changes for good. Quitting ends every waiting change at once.
- **Rapid hotkey changes:** changing the dictation hotkey several times in a row always ends with exactly one registration, the last one you chose.
- **Hotkey runtime on macOS, Windows and Linux:** the right Control and right Alt keys are recognised as single hotkeys on Windows; the Linux X11 modifier watch stops when the hotkey changes; the macOS modifier key no longer goes wrong after the permission dialog or a lost event; Smart Mode and the selection edit on Windows and Linux no longer wait for a release that never comes (hold is limited to tap there).
- **Last words are kept when you stop:** recording keeps running for a quarter of a second after you release the hotkey, so the end of a sentence is no longer cut off. Cancelling still stops at once. A dictation that is only whitespace is reported as empty instead of saving a blank history entry.
- **Unconfirmed paste notice:** when macOS or Windows refuses the clipboard receipt, WhisPaste now shows a calm notice that the text is on the clipboard, instead of failing silently. The previous clipboard content is still not restored.
- **Import queue at large text:** with text scale 1.3 and up the import header stacks its text above the Add files button, and a long import queue scrolls in its own area, so the search bar and the history list stay on screen. The reduced-motion setting also stops the moving bar of a transcribing import; the elapsed time stays.
- **Floating button mic matches the wave colour:** while recording, the button's microphone uses the chosen wave colour, like the dot in the overlay. Before, it stayed red, which clashed with an amber background or a black wave. The settings preview now shows the button at rest and while recording, side by side.
- **Failed pastes are reported everywhere:** a paste from the side panel or the snippet picker that does not land now gives the same warning as a dictation: a message, the tray entry and the error tone, and the message says the text is on the clipboard. An unconfirmed paste and a missing permission warn; Linux without a receipt stays quiet.
- **Pasting a list into the auto-paste block list:** line breaks in the manual entry field become one app per line. Blank lines are dropped and spaces trimmed. Before, the lines were joined into one wrong identifier.
- **Stuck speech engine:** when the speech engine stops answering, Settings shows a hint to restart WhisPaste instead of failing silently.
- **Faster final transcription:** the last transcription of a dictation now runs at full CPU threads. Before, it ran with reduced threads and the live preview kept running.
- **Speech model stays loaded during a dictation:** an idle unload that comes due while a transcription is still running no longer unloads the model under the next dictation.
- **Stuck engine fails sooner:** after a transcription got stuck, the next dictation reports the problem after about 2 seconds instead of waiting 30 seconds.
- **Hotkey under Wayland explains itself:** if the desktop does not bind the hotkey for other apps, Settings and onboarding say why, offer "Reconnect" and show the command for a custom shortcut. Unpackaged Linux builds install their own GNOME launcher entry, so the desktop can find WhisPaste.
- **Linux: Auto-Paste asks before it gets keyboard access:** the .deb package no longer grants /dev/uinput when it is installed. WhisPaste asks first and needs your administrator password. You can remove the permission again in the settings.
- **Crash reports keep less personal data:** file names, local paths and imported document text are removed from crash reports, their breadcrumbs and log entries. Only the file extension and the error type remain.
- **GPU crashes stop repeating:** after a second crash while a GPU speech model loads, WhisPaste keeps that model on the CPU. A successful warm-up no longer resets the crash count, and a GPU transcription that hangs moves to the CPU engine once.
- **CUDA pack asks for the NVIDIA licence:** the optional CUDA pack downloads only after you accept the NVIDIA CUDA licence. The consent dialog shows the full licence text before you accept, and your consent applies to that text.
- **CUDA needs your consent to load:** an installed CUDA pack is used only after you accept the NVIDIA licence, also after a headless download. Without that consent WhisPaste uses Vulkan or the CPU, and the settings row asks you to review the licence.
- **Settings changed during start-up are kept:** a change made before your stored settings finished loading is applied once they are loaded, instead of being overwritten by the defaults.
- **A damaged model file is replaced cleanly:** when a downloaded model turns out to be damaged, WhisPaste deletes it and downloads it again without stopping with a "file not found" error.
- **The keep period of failed recordings is final:** a kept recording past the keep period you set is deleted when you try it again, instead of being transcribed. WhisPaste says so.
- **Model downloads resume after a sibling cleanup:** a paused model download is no longer deleted by another download's cleanup, so it can continue where it stopped.
- **Automation API: stalled requests time out:** a request whose body stops or trickles in gets a 408 response after 30 seconds instead of holding the connection open.
- **The speech engine is never unloaded during a running transcription:** a model switch or idle unload waits until the current transcription has returned. Quitting no longer waits for it, and if the engine is still busy after a long wait, WhisPaste shows a notice to restart the app instead of freeing it under a running call.
- **Computers with less than 8 GB of RAM start:** WhisPaste no longer stops at start on such machines. It starts and recommends the compact speech model.
- **Hotkey after idle:** the first press after idle starts recording at once, and a press right after a released start is no longer dropped.
- **Failed transcriptions:** the audio of a failed transcription stays parked and can be retried; unfinished or orphaned audio files are cleaned up. A recording interrupted by a crash or quit during capture or transcription is transcribed once at the next start. Long cloud uploads are sent in parts: a retry after a rate limit, server error or timeout sends only the parts that are still missing. Failed recordings are kept for 7 days by default; Settings > Privacy & data sets 1 to 30 days, and Settings and the history detail show until when each one is kept; the history detail also offers Try again and Discard right there. The privacy page of the onboarding shows the keep period in one line and explains the details on request.
- **Audio not kept stays off the disk:** with "Keep recent audio" off, a dictation whose history save failed keeps only its text. No audio file is left behind for it.
- **Sleep and wake:** a recording in progress finishes before the computer sleeps, and the speech engine is checked again after wake.
- **Database from a newer build:** WhisPaste shows a start screen instead of failing when the database was written by a newer version.
- **Database upgrades are all or nothing:** the upgrade steps run as one unit. If one fails, all of them are undone and the database keeps its previous version and data. If the file is busy or the disk does not respond, a start screen says so and offers to try again. The checks that follow an upgrade are safe to repeat at the next start. On Windows, moving the history database out of the old nested folder checks the copy before anything is replaced, keeps the original in use if any step fails, and keeps the rescue copy until the moved database passes an integrity check.
- **Snippet picker trigger:** the trigger word is limited to 64 characters on one line, and a word still being typed is saved when the app leaves the foreground.
- **Blocklist entry:** control characters can no longer be typed into the manual entry of the auto-paste blocklist.
- **Side panel:** Escape closes it, a failed load says so instead of showing the empty state, and its tabs have 48 px hit areas.
- **Live preview ends with the recording:** the preview shown while dictating also stops after a delivered, empty or Smart Mode dictation, not only after a cancel.
- **History PIN:** content is withheld only while a PIN is set.
- **Footer version:** the footer hides the app version until it is known, instead of showing a placeholder.
- **PIN lock covers copied text in the side panel:** while the recordings are locked by a PIN, the clipboard tab of the side panel shows no copied text and cannot paste it.

- **GPU crashes fall back to the processor:** graphics-driver errors that used to close WhisPaste during model load now end in a CPU fallback with a logged reason. The app checks the graphics card in a separate process before using it. If the check fails, WhisPaste uses the processor and shows a notice; a graphics-driver update triggers a new check by itself, and Settings > Speech recognition offers "Check again" at any time.
- **Model downloads work on a fresh Windows install:** the onboarding model download failed with "CERTIFICATE_VERIFY_FAILED" on new Windows notebooks, because Windows fetches some certificate authorities only when another program first needs them. WhisPaste now ships the Mozilla certificate list and trusts it in addition to the Windows store, so the download works on a fresh installation. Company proxies and antivirus software still work as before. If a connection still cannot be verified, the download now says so in plain words, with the next step (check the device's date and time, or a program that inspects connections).
- **Dictation pastes into the app you were in at the hotkey:** WhisPaste captured the paste target a second time after transcription. When WhisPaste itself was in front by then, the target was lost and the text was not pasted into the app you were using (seen with Windows Terminal). The target is now kept from the moment the dictation starts.
- **Fewer false punctuation and repetition cuts:** the spoken word "point" and its German equivalent stay plain words in common idioms and in clock times, such as "to the point", "point by point", "the crux of the matter" and "point 12 o'clock". A short repeated phrase such as "yes. yes. yes." is no longer cut, only long repeated sentences. The same text cleanup now runs for every speech engine, Parakeet included, and with punctuation removal on, the history shows the pasted text.
- **macOS permission prompts in your app language:** the microphone prompt and the prompt for pasting into other apps now appear in German, Spanish, Portuguese, Russian and Hebrew, each with its reason. Other languages still see English.
- **Import panel scrolls with the history:** the "add files" panel is the first row of the history list instead of a fixed bar above it. At a large text size it no longer pushes the list out of view, and it stays reachable on an empty, loading or failed history. In a narrow pane (below 400 px) it shows only an add-files icon.
- **A hotkey that another app already owns is now noticed on macOS and Windows:** WhisPaste used to take every answer from the system as "registered", so a combination held by another app showed no warning. It now asks the system for the real result, shows the conflict in Settings and onboarding and falls back to the safe combination, as it already did on Linux. The automatic re-registration also reports when the system refuses the combination.
- **Hold, tap and double tap no longer depend on how fast the app reacts (Linux, X11 sessions):** on Linux with X11, WhisPaste now decides from the times the keyboard itself reports (the press length and the gap between two taps), not from when the message reached the app. A busy moment in the app can no longer turn a real hold into a tap or break a double tap. On macOS and Windows the same now applies to modifier-only hotkeys (see "Hold, tap and double tap stay right on a busy computer"). Where the desktop sends no key times (Wayland shortcut portal, stampless events), the arrival time decides as before.

### Known issues

- **No downgrade to 1.4.x after updating.** 1.5.0 stores your recordings, notes, dictionary and snippets encrypted with your device's data key. Version 1.4.x cannot read this data and does not warn you, so do not reinstall 1.4.x once 1.5 has started. If 1.5 causes trouble, install the newest 1.5.x update instead and tell us on the Feedback page; fixes come as new 1.5.x versions.
- **Flatpak: not on Flathub yet, voice-note import unverified.** WhisPaste is not published on Flathub yet. If you build the Flatpak yourself from `packaging/flatpak`, importing Ogg/Opus and M4A files depends on libopusfile and GStreamer in the GNOME runtime, which is not verified yet. Until it is, use the .deb, AppImage or Windows/macOS builds for importing those formats, or convert the file to WAV.
- **Linux AppImage on Ubuntu 24.04: automatic pasting not yet confirmed on a fresh system.** The AppImage is built for Ubuntu 24.04 and newer; starting, the one-time paste confirmation and pasting were tested on Ubuntu 26.04 only. A full run on a fresh Ubuntu 24.04 desktop (confirmation, dictation, paste, global hotkey, "Copy command") is still open. If something does not work there, please tell us on the Feedback page (#478).

## 1.4.2

### Fixes

- **No more crashes with accessibility tools on Windows:** while a screen reader or another accessibility tool was running, resizing the window or typing into the History search could close WhisPaste. Thanks to the user who reported it in detail.

## 1.4.1

### Fixes

- **CUDA pack download works:** the optional CUDA pack for NVIDIA GPUs (Windows and Linux, Speech recognition → GPU acceleration) failed with a network error in 1.4.0 because the pack was not available at its download address. It now downloads from its own release. Not part of the Microsoft Store version.

## 1.4.0

1.4 adds voice-driven editing of selected text, spoken line breaks, optional filler-word removal, push-to-talk on Linux (experimental) and an interface in Spanish and Brazilian Portuguese. Smart Mode stays loaded between runs, more hardware runs without crashing, and the crash-report opt-out now applies from the first start.

### Highlights

- **Edit selected text by voice:** select text, press the new hotkey and say what should change. Off by default.
- **Line breaks by voice:** say "new paragraph" or "new line" to start a new paragraph or line.
- **Recordings up to 60 minutes:** the recording limit now goes up to 60 minutes, with Unlimited at the far right.
- **Remove filler words:** optionally drop "um", "äh" and similar from dictation. Off by default.
- **Push-to-talk on Linux (experimental):** hold a hotkey to dictate, on X11 and on Wayland.
- **Smart Mode keeps its model loaded:** repeated rewrites no longer reload the local model every time.
- **More hardware runs cleanly:** CPUs without AVX2 and older NVIDIA cards no longer crash or hang WhisPaste.
- **Crash-report opt-out from the first start:** turning it off also covers people who opted out in an earlier version.
- **Start and stop from a desktop shortcut:** `whispaste --toggle` controls the running app.
- **Spanish and Brazilian Portuguese interface:** the app now speaks six languages.
- **Calmer, clearer interface:** history and notes rows have a clear hierarchy, long entries keep a readable width, and settings sections are picked from one menu.
- **Support WhisPaste from the app:** a new Support page collects the ways to help. Store versions offer optional one-time tips through the Microsoft Store and the Mac App Store. Tips unlock nothing; the app stays complete without them.

### New Features

- **Optional CUDA pack for NVIDIA GPUs (Windows and Linux):** on NVIDIA RTX and GTX 16 cards, Speech recognition offers a separate, checksum-verified CUDA download under GPU acceleration. You can cancel, switch off or remove it there. Without a working driver WhisPaste stays on Vulkan, and a crash while loading CUDA switches the option off. Not part of the Microsoft Store version.
- **Refreshed interface:** history and notes rows show title, preview and details in a clear order, the selected entry stands out, and the history detail keeps a readable line width on wide windows. Settings replace the row of section chips with a section picker. Word counts read "approx. 27 words" instead of "~27 w".
- **Support page:** About › Support WhisPaste lists every way to help: GitHub Sponsors, Ko-fi and PayPal on direct downloads, native one-time tips on the Microsoft Store and the Mac App Store, plus rating, starring and sharing. A small chip in the status bar leads there and turns into a thank-you once you have supported the project; supporters can hide it, and Settings › Interface brings it back. A verified store purchase earns a small supporter badge. Nothing in the app is locked behind a payment.
- **Edit selection by voice:** a new hotkey, off by default, copies the current selection, records your spoken instruction and replaces the selection with the result. "Shorter", "improve" and "translate" work as quick actions in all six UI languages; any other sentence is passed on as a free-form instruction. It uses your Smart Mode engine (local or cloud). Nothing is written to history, and your clipboard is always restored.
- **Spoken line breaks:** say "new paragraph" or "new line" and WhisPaste inserts a real paragraph or line break. Works in all six UI languages (for example "neuer Absatz" / "neue Zeile", "nuevo párrafo" / "nueva línea") and follows the transcription language. On by default; turn it off under Speech recognition.
- **Line breaks in replacements:** a replacement can now contain `\n` for a line break (`\\n` keeps a literal backslash-n). Existing replacements that contained a literal `\n` now insert a line break.
- **Filler word removal:** new toggle under Speech recognition, off by default. It removes unambiguous fillers as whole words before Smart Mode and replacements run ("um" only in English). The history keeps the original transcript.
- **Push-to-talk on Linux (experimental):** key release is read through XInput2 on X11 and through the GlobalShortcuts portal on Wayland (GNOME 48+, Plasma 6+). If the desktop does not report key release, the hotkey stays toggle-only. Settings and onboarding carry an "Experimental" badge until this has been verified on real GNOME and KDE desktops.
- **Smart Mode on Linux (experimental):** Linux packages include the on-device engine. If its library is missing, the option stays disabled with a hint.
- **Start and stop from a desktop shortcut:** `whispaste --toggle` starts or stops dictation in the running instance, `whispaste --cancel` discards it. Without a running instance, `--toggle` starts the app and begins dictation after the first frame. SIGUSR2 also toggles on Linux and macOS. The README shows GNOME and KDE setup.
- **Spanish and Brazilian Portuguese interface:** WhisPaste's interface is now available in Spanish and Brazilian Portuguese alongside English, German, Hebrew and Russian. It follows your system language and can be changed in onboarding and settings. The translations have not yet been reviewed by native speakers; feedback is welcome.
- **Transcribe files from the command line:** `whispaste --transcribe-file <wav>` runs the app's transcriber on a WAV file and prints the text (`--json`, `--engine`, `--model`, `--replacements`). Meant for scripting and latency checks.

### Bug Fixes

- **Recording a hotkey that is already in use.** While the hotkey recorder listens, WhisPaste takes its own hotkeys off the system and puts them back when the recorder closes, saved or cancelled. Pressing the current combination again (for example Cmd+Ä) is now recorded instead of showing only the modifier, and a press while recording never starts a dictation.
- **Smart Mode uses all CPU cores.** The local engine ran with 4 threads on every machine and now follows the CPU's core count.
- **Smart Mode follows the GPU setting** and retries on the CPU when the model fails to load on the GPU. A rewrite that was cut off is reported instead of being pasted.
- **More reliable GPU detection:** on Windows a slow first detection no longer keeps the app on the CPU until restart, and graphics memory above 4 GB is read correctly. On Linux laptops with two GPUs, name and memory come from the GPU that is actually used.
- **Windows: quitting no longer crashes.** The native window now cleans up on destruction, and the app ships its own VC++ runtime, so an older system runtime cannot crash a mutex call on exit.
- **Windows: on-device Smart Mode could fail to load** (error 127) when Whisper had loaded first. The two engines' ggml libraries now have their own names.
- **Parakeet: recordings shorter than 0.1 seconds no longer crash the engine.** An empty or near-empty recording is treated as silence instead of reaching sherpa-onnx, which could abort the process on Windows.
- **Parakeet: long recordings no longer fail.** Audio beyond about 35 seconds is split into chunks of up to 25 seconds at the quietest point.
- **Native engine errors no longer crash the app.** C++ exceptions from Whisper (including Vulkan) and sherpa-onnx become errors instead of aborting the process.
- **Model downloads resume** after a dropped connection. Remaining failures are reported as retryable network errors.
- **Windows: deleting or replacing model and log files** no longer fails while a previous handle is still held; short sharing violations are retried.
- **Windows: dictation reaches the clipboard history less often.** A clipboard that another process holds open for a moment is retried for up to about 100 ms, instead of falling back to a plain write that Win+V records (#146).
- **Older NVIDIA cards run on the CPU in automatic mode.** GeForce 4xx to 7xx and Quadro, Tesla or GRID K cards crashed or hung on the GPU path. Choosing GPU manually still uses the GPU.
- **CPUs without AVX2 no longer crash the engine.** Windows and Linux ship several CPU backend variants and pick the best instruction set at runtime. On Linux, a model load no longer aborts when the backend library is missing.
- **Privacy: the crash-report opt-out takes effect immediately.** Turning it off writes a marker and closes Sentry, so later starts never initialise it, including native crashes. Users who opted out in an earlier version are covered from their first start. Usernames are removed from paths and free text in reports. The app checks for updates on start and every 24 hours only while "Check for updates" is on.
- **Cancelling a transcription is final.** Starting a new recording right after cancelling no longer lets the cancelled text be pasted, the stop hotkey works again immediately, and an aborted edit-selection or snippet run can no longer paste into the next dictation.
- **GPU crashes during transcription fall back to the CPU.** The retry now really runs on the CPU engine instead of on the same GPU context.
- **Clipboard:** an empty or non-text clipboard is no longer overwritten with an empty string after pasting, the previous text is restored when typing had to be used as fallback, and edit selection waits a little longer for slow apps to copy.
- **macOS: hotkeys added in a later version default to ⌘** instead of Ctrl, matching a fresh install.
- **Rare crash when the speech engine answered twice** is fixed.
- **Automation API hardening:** the local API only answers requests addressed to localhost, and its port is no longer opened in shared mode.
- **Crash reports:** extra diagnostic fields are scrubbed of user paths too, and unrecognised graphics adapters are reported by name so they can be supported.
- **Mac App Store 1.3.0:** the feedback form and telemetry were inactive, because the build was missing its configuration.
- **A missing speech model is visible before you dictate.** If the selected on-device model is not downloaded, the status bar says so instead of "Standby", the selected quality tier in Settings offers the download, and the dictation hint downloads it with one click, showing its size.
- **macOS: Auto-Paste permission recovers on its own after updates.** macOS ties the Accessibility permission to the app's identity and signature. The direct download and the Mac App Store version shared one identity, so switching between them could leave an entry that looked enabled but did nothing. The direct download now has its own identity (`de.whispaste.direct`) and takes over your settings on first start; macOS asks for the permission once. If an entry still goes stale, WhisPaste detects it and walks you through fixing it instead of restarting in a loop.
- **macOS: on-device Smart Mode is included again.** The macOS download and the Mac App Store build shipped without the Smart Mode engine, so the option stayed disabled. Release builds now fail instead of leaving it out.

### Improvements

- **Faster Whisper transcription:** the bundled whisper.cpp moves from 1.8.4 to 1.9.5. On an Apple M5, local transcription of 18 German dictations took about 44 % less time with identical text (large-v3-turbo q5_0, Metal). On macOS the CPU part now picks the build that fits the Mac's chip at startup, so older Apple Silicon Macs get a matching build instead of one tuned for the newest chips.
- **Parakeet on the GPU:** Parakeet now runs on the GPU through whisper.cpp's ggml backends (Metal on macOS, Vulkan or CUDA elsewhere) and falls back to the CPU engine when no GPU is available or a GPU run fails. On an Apple M5, 18 German dictations (456 seconds of audio) took 7.0 seconds instead of 38.3 seconds on the CPU engine, with the q8_0 model. On a Windows laptop with Intel Iris Xe graphics (Vulkan), 18 German recordings (276 seconds) took 14.1 seconds instead of 27.1 seconds. German word error rate dropped from 8.5 % to 7.1 % in the same test. The model is downloaded with the Parakeet model and checked by its SHA-256 before every load.
- **Paste without the fixed wait:** when the app you dictated into is still in front, which is the usual case, WhisPaste pastes as soon as the hotkey's modifier keys are released instead of always waiting the Auto-Paste delay (200 ms by default). Apps that first have to be brought to the front still get the full delay. macOS and Windows.
- **Snappier first recording:** the sound engine no longer opens the audio device ahead of the microphone on the first hotkey press.
- **Longer recording limits:** the maximum recording length offers steps from 30 seconds up to 60 minutes, and Unlimited sits at the right end of the slider. Long recordings get a transcription budget that grows with their length instead of a fixed 5 minutes.
- **Hold-or-tap push-to-talk:** a new option for macOS and Windows (disabled on Linux). A press starts recording. If you hold the key for at least 300 ms and release it, recording stops, as with classic push-to-talk. A shorter press keeps recording until the next press. The option applies to the main and Smart Mode hotkeys.
- **Live preview shows the newest words:** the one-line overlay keeps the words you just said visible instead of cutting them off at the end.
- **Dictation stops faster:** stopping cancels a running live-preview decode instead of waiting for it.
- **Smart Mode keeps its model warm:** the local model stays loaded in a background worker and is unloaded after the speech-recognition idle timeout (5 minutes by default). On machines with less than 12 GB RAM it is unloaded after every run. Timeouts cancel generation.
- **Clipboard restored sooner:** after pasting, the previous clipboard returns about 150 ms after the target has read the paste, not after a fixed 500 ms, and is left alone if another app copied something in between. Linux is unchanged.
- **Clearer message when no microphone is found** instead of an error report.
- **Linux .deb sets up Auto-Paste permissions:** the package loads `uinput` and applies the udev rule during installation, so Auto-Paste works without a reboot or re-login.
- **Homebrew cask requires macOS 12 or later,** matching the app itself.
- **Hebrew and Russian translations:** 52 missing strings added.

## 1.3.0

With 1.3, WhisPaste bundles the features of the last few weeks into a single minor release. The details for each version are listed below.

### Highlights since 1.2.60

- **Smart Mode:** clean up, shorten or translate dictation before it is pasted — locally on the device (macOS/Windows) or via OpenAI, with its own hotkey and target language.
- **Interactive snippets:** text templates with blanks that WhisPaste fills in field by field through dictation.
- **Side panel:** clipboard history at the screen edge — now also on Linux, and on the left or right edge.
- **Live transcript:** the recognized text appears in the recording overlay while you are still speaking.
- **Learns from corrections:** repeated corrections in the history are suggested as replacements.
- **Discard recording:** Escape or the X in the overlay discards a recording without transcribing or pasting it.
- **History protected by PIN:** a privacy lock for the history, side panel, button menu and automation API, with automatic locking.
- **Local automation API:** control WhisPaste over HTTP from scripts and tools (see `AUTOMATION_API.md`).
- **New languages:** Russian and complete Hebrew.

### New Features

- **New in WhisPaste:** the notice introduces the new PIN protection for the history.

- **History:** optional PIN protection (4–8 digits) for the history. When a PIN is set, the side panel no longer shows transcripts, the context menu of the floating record button no longer shows recent entries, and the local automation API responds with `423 history_locked` until the history is unlocked. The history locks itself again automatically at app start, when minimized to the tray, and optionally after a configurable period of inactivity (1–60 minutes). Repeated wrong entries trigger an increasing wait time; "Forgot PIN?" deletes the history and removes the PIN. The PIN is a visual lock, not encryption.
- **History:** new setting "Hide history on open" — the history page only shows its content after a click on "Show history", e.g. for screen sharing.

### Bug Fixes

- **Autostart:** "Start Minimized" is now reliably respected — WhisPaste starts in the tray at login instead of opening the main window.
- **Side panel:** when docked to the right screen edge, the panel still had the shape of a panel docked to the left. Corners and close button are now mirrored and point toward the screen center, including in right-to-left languages.
- **Linux:** with the system keyring locked, WhisPaste hung at startup without a window, tray icon and hotkey. The app now starts normally and treats stored API keys as temporarily unavailable (#151).
- **macOS:** if the app was in a path containing spaces (e.g. "WhisPaste 2.app"), the tray icon was missing and the Dock icon stayed visible after closing the window. The tray icon now loads regardless of the install path.

## 1.2.79

### New Features

- **Settings:** the clipboard quick-paste panel can now dock to the left or right screen edge (new setting "Panel Position") instead of always appearing on the left (#150).

### Bug Fixes

- **Settings search:** several rows that do exist (including "Panel Position", "Deepgram API Key", "Live transcript") returned no results despite an exact search term. Missing keywords were added to the search registry.
- **Side panel:** toggling the setting off and on once could leave the panel permanently non-functional — it no longer opened when the mouse moved to the screen edge. The on/off cycle is now reliably reversible.
- **Sound feedback:** with sound feedback enabled, the audio device — including a Bluetooth headphone connected via multipoint — stayed open until WhisPaste quit, blocking other apps' audio. The device is now released after 30 seconds of inactivity (#148).

## 1.2.78

### New Features

- **Automation API:** `dictation/trigger` can now take a per-call Smart Mode preset (`smart_mode_preset`) and its own silence timeout (`silence_timeout`, `0` disables auto-stop), instead of always using the globally configured defaults.
- **Settings:** the anchor chip bar now highlights the section currently in view while you scroll through the page, instead of only flashing briefly when tapped.
- **Recording:** a real "Cancel" action for an ongoing dictation — it discards the recording instead of transcribing it.

### Bug Fixes

- **Windows:** auto-paste now writes transcripts to the clipboard through the same history-exclusion path as the rest of the history. Dictations previously still landed in the Win+V clipboard history even though it was disabled there (#146).
- **STT:** the `initial_prompt` is now correctly truncated to whisper.cpp's actual token budget instead of exceeding it.

## 1.2.77

### New Features

- **New local automation API** (loopback only, HTTP): start/stop dictation via an external trigger, fetch the last history entry, insert text snippets — including port fallback, a configurable port, a status endpoint, a status bar display, and linked documentation in the settings.
- **Live transcript preview:** the overlay can now show the text live during recording, instead of only after stopping.
- **Text replacements now learn automatically from repeated corrections** — via a voice command ("korrektur: …" / "correct: …") or by manually editing a history entry. Make the same correction twice and WhisPaste suggests it as an automatic replacement in a dedicated review view, including undo directly on the confirmation toast.
- **Settings:** new anchor chip bar for quick section navigation, plus a visual card selector for the overlay size (instead of a dropdown).
- **History:** entries now show the diff against the original transcript, along with target app and character count as metadata.
- **Smart Mode:** the introduction notice now shows a before/after example.

### Bug Fixes

- **Keyboard/screen reader accessibility added** for history titles/transcripts, the notes header, the low-RAM warning screen, and the Markdown toolbar.
- **CSV export:** closed a formula injection gap with leading whitespace (it also affected the tags column).
- **History/notes in the trash:** copy and duplicate are now consistently reachable, or correctly shown/hidden.
- **Various stability fixes in the automation API** (race conditions on sync/shutdown, a stuck error state after disabling, rebind after server restart, MAS sandbox entitlement).
- The success sound on dictation now stays silent if automatic pasting has already failed.

## 1.2.76

### Bug Fixes

- **Global hotkeys sometimes registered the wrong physical key on non-US keyboard layouts (e.g. German)** (e.g. Ctrl+# was registered as Ctrl+^). Hotkey capture now queries the active Windows keyboard layout live, instead of relying on a static US-layout mapping. (#108)

## 1.2.75

### Bug Fixes

- **The clipboard quick-paste panel kept appearing on mouse hover even though it was disabled in settings.** Disabling it now also properly tears down the associated native control controller.
- **An empty, unlabeled card could appear in settings between "Factory Reset" and "Introduction"** — the "Updates" section is now completely hidden on store- or package-managed installs (Mac App Store, Microsoft Store, package managers), instead of just being empty.
- **The "Rate" button on the Mac App Store always opened GitHub instead of the Mac App Store rating page.** Rating buttons (settings and the rating dialog) now respect the actual distribution channel: Mac App Store → Mac App Store, Microsoft Store → Microsoft Store, installer/portable → GitHub.

## 1.2.74

### New Features

- **Notes: new "Duplicate" action directly in the note editor toolbar**, placed alongside copy and export.

### Bug Fixes

- **Smart Mode "On-device" (local AI post-processing) never really worked on Windows in shipped builds** — the files it needs were never shipped with the Windows build. This is now fixed.
- **The diagnostics wrongly reported missing speech recognition files on Windows**, even though the installation was complete and working.
- **Window controls in the title bar** (minimize/maximize/close) are now fully keyboard-operable and accessible to screen readers.

## 1.2.73

### New Features

- **Export remembers the last chosen format.** On the next export of history or notes, TXT/MD/CSV/JSON/DOCX is already preselected instead of always jumping back to the first option.

### Bug Fixes

- **Store ratings on the website now show the real release date** instead of the time we last synced them.
- **The history title stayed at its old value after editing a dictation.** The title is now re-derived on every text change. A custom title you set yourself stays untouched, and a dictation that was accidentally cleared completely keeps its last title instead of losing it.
- **Hints for failed auto-paste (no target window, missing permission, blocked by administrator rights) were hardcoded in German**, so they did not appear in the selected language for non-German users.

### Maintenance

- **Order of support actions after download changed:** the store rating for the respective operating system now comes before the GitHub star, since it contributes more directly to discoverability in that store.
- **Anonymous usage statistics extended** by a weekly rotating cohort identifier for more reliable returning-user analysis, without permanently identifying a device. Details are in the privacy policy (section 15).

## 1.2.72

### New Features

- **Russian language: WhisPaste is now also available in Russian.** Fourth interface language alongside German, English and Hebrew — a community contribution.

### Bug Fixes

- **Hebrew translation completed:** 88 previously untranslated interface texts (including Smart Mode, text replacement import, side panel) added.
- **Language selection in floating windows** (e.g. the quick-paste panel) did not automatically pick up newly added interface languages — recently this affected Russian. The selection now derives from the actually shipped language list instead of a separately maintained copy.

## 1.2.71

### New Features

- **Smart Mode: optional, local AI post-processing directly after transcription.** Three presets: "Cleanup" removes filler words and corrects punctuation, "Concise" tightens the text without losing facts, "Translate" translates it into one of seven validated target languages (German, English, Spanish, French, Portuguese, Mandarin, Russian). Runs on macOS and Windows on a local AI model — the text never leaves your device. Optionally usable via your own OpenAI cloud provider. Presets can be assigned to the main hotkey or to a separate second Smart Mode hotkey (with its own target language), and can also be applied to existing history entries afterwards.
- **Interactive snippets:** templates with several fields, through which WhisPaste guides you field by field (with an announcement before each field) before inserting the finished text in one piece. This extends the existing snippets for multi-part, recurring dictations.
- **Vocabulary import for text replacements:** import your own term lists, with fuzzy matching against existing replacements and a review step before they are adopted.
- **Linux catches up with macOS/Windows for the quick-paste panel:** native side-panel window, including a clipboard snapshot when it opens. On macOS, entries can now also be dragged directly out of the panel.

## 1.2.70

### Bug Fixes

- Dictation across several sentences without a pause: under increased system load (e.g. a running fan), WhisPaste now detects more reliably when speech is replaced or dropped by an endlessly repeating phrase, and punctuates longer dictations consistently. For this, long recordings are internally split at real speech pauses into smaller chunks before they go to speech recognition.
- The quick-paste panel now reliably closes as soon as focus leaves the app, and no longer unnecessarily re-encodes its rows when closing.

## 1.2.69

### New Features

- **New quick-paste panel that slides out on hover at the left screen edge** (macOS and Windows): quick access to transcriptions, snippets and a new clipboard history, without bringing the app to the foreground. The clipboard history lives purely in memory and is cleared when the app restarts. A new switch in settings disables the panel entirely if needed.
- **New notice mechanism "New in WhisPaste":** after an update, a one-time dialog appears that presents new features with a screenshot (currently: the quick-paste panel and the snippet quick access). It can be reopened at any time from settings, including a link to this changelog.
- Added a link to the maintainer's X profile on the About page and in the website footer.

### Maintenance

- The "Made with ♥ by …" notice on the About page is now addressed to WhisPaste itself instead of an individual person.

## 1.2.68

### New Features

- Snippets can now also be duplicated and copied directly from the list, analogous to the existing actions for history notes.

### Bug Fixes

- **Windows: the native window title bar had recently started appearing twice** (the system title bar in addition to the app's own title bar). An internal state was not reset at program start, which permanently blocked suppression of the Windows title bar.
- Windows: a rare crash when closing the window has been fixed.
- Ending a voice recording could rarely collide with a transcription still running. It is now reliably sequenced, with a short timeout safeguard.
- The button to stop showing this notice again was not reachable via keyboard.

### Maintenance

- Performance: list filtering (settings search, snippet and history lists) now uses precompiled regular expressions instead of repeated `toLowerCase()` calls inside the loop.

## 1.2.67

### New Features

- **WhisPaste is now officially available on the Mac App Store** (signed, sandboxed, automatic updates via the store — analogous to the Microsoft Store on Windows). The free GitHub DMG remains an equivalent alternative with an identical feature set and no restrictions.
- **Linux catches up with Windows/macOS for the snippet quick access, and auto-paste is now possible on Linux too:** transcribed text can now also be pasted automatically on Linux (via a virtual keyboard). This requires a one-time manual setup of a udev rule (`packaging/linux/71-whispaste-uinput.rules`, instructions inside). Without this step, the clipboard fallback remains. The snippet quick access now opens on Linux as its own system-integrated window, directly at the mouse position.
- **New native interface for the snippet quick access on Windows** — it now also opens as its own small window at the mouse position instead of in the main app.
- **The auto-paste step in the Windows first-run setup is now a real on/off decision** instead of a non-functional info page. Previously it said that auto-paste was ready, even though the feature was off by default and could not be enabled anywhere in the first-run setup.
- A snippet can now be duplicated directly from the list.
- New copy action for individual history notes, analogous to edit/delete.
- Revised visual appearance across large parts of the app (settings, About page, history, recording bar, first-run setup) — a more consistent material design language and a tidier, more focused look.

### Bug Fixes

- **Auto-paste did not reliably recover after a missing or revoked permission in some cases.** Several related spots were hardened: the permission is now repaired right at the point of failure instead of only via settings, an already fixed state no longer asks again unnecessarily, and the Mac App Store variant now reliably hands the permission dialog over to the correct follow-up state.
- The transcribing waveform in the overlay was sometimes frozen instead of animating.
- A brief flash of the overlay at the screen corner when opening has been fixed.
- Overlay texts now follow the language set in the app instead of the operating system language setting.
- The "floating button" card in settings also appeared on platforms that do not support this feature.
- Occasional duplicate screen reader announcements in the history notes area (accessibility features) have been fixed.
- Various alignment and layout corrections in the revised first-run setup, including missing Hebrew translations for the "Let's go" step.

### Maintenance

- Several internal performance audits (app lifecycle/memory leaks, scope of UI rebuilds, network/IPC, resources/caches, UI rendering) removed unnecessary recalculations, memory allocations and file copies — among others in the history with many entries, when uploading to cloud speech recognition, and when cleaning up aborted model downloads.

## 1.2.66

### Bug Fixes

- **The maximize button in the title bar (Windows/Linux) had no label for screen readers.** It now announces either maximize or restore, depending on the window state, instead of staying silent.

### Maintenance

- Internal Store compliance fix (part of a not-yet-completed, not-live Mac App Store submission — the only current macOS distribution channel remains the GitHub DMG): multi-instance detection previously ran over a local network socket, for which the required sandbox entitlement (`network.server`) was rejected at App Review as unjustified. It now runs via a file lock instead, with no network at all. Two further unused sandbox entitlements (`cs.allow-jit`, `files.user-selected.read-write`) were removed at the same time, and the privacy manifest was extended with the disclosure about optional cloud speech recognition audio data that was already published elsewhere.
- Noticeably smoother history list with thousands of entries (unnecessary object allocations in date grouping removed), and a smoother recording overlay (waveform now renders in its own compositing layer).
- Further Store compliance corrections (second review round of the same, still not-live Mac App Store submission): the buttons on the permission explanation pages in onboarding used labels that seemed to anticipate the real macOS system dialog that follows. They are now uniformly labeled "Continue". The hint text for the Accessibility permission now explains more clearly that WhisPaste uses this permission only to insert text, not for real Accessibility features. The one-time "Thanks for your support!" notice with the Store rating request previously appeared right after the first-run setup. It now appears no earlier than after 12 completed recordings, once a real benefit has already arisen.
- The macOS app bundle name in the DMG and in the ZIP download was lowercase (`whispaste.app` instead of `WhisPaste.app`). This only affected the capitalization of the icon label in Finder, not functionality. It is now consistently "WhisPaste".

## 1.2.65

### Bug Fixes

- **An interrupted model download could get stuck permanently with an HTTP 416 error** instead of retrying. If the partial file already downloaded during an earlier abort was as large as or larger than the current file on the server, the server refused every further resume attempt. WhisPaste now discards the old partial file automatically and restarts the download once from scratch.

### Maintenance

- Internal build/Store tooling fixes: the macOS build temporarily ran into a permission error when embedding the local Whisper engine, and the German Microsoft Store screenshots ended up in a wrong, never-displayed store entry instead of the real German listing.

## 1.2.64

### New Features

- **WhisPaste now proactively checks on every start whether the microphone and auto-paste permissions are still present** — no longer only once during the first-run setup. If one is missing, an always-visible dialog leads directly to the correct system setting, even when WhisPaste is only running in the background. Anyone who never uses auto-paste (clipboard mode) is no longer bothered by this.
- **New switch "Trim trailing silence"** uses whisper.cpp's built-in speech detection to cut appended silence/noise out before transcription. This reduces invented word fragments at the end of a transcript, in addition to the existing safeguard. It is enabled by default, can be switched off, and is only available with the local Whisper engine.

### Bug Fixes

- **The auto-paste permission could get stuck in a restart loop with no visible way out.** The grant dialog and System Settings could overlap each other, a restart sometimes ended in an empty state with no running app, and if the permission still failed after a restart, WhisPaste again only showed the original permission hint instead of honestly saying that the restart had achieved nothing. All four points are fixed, including a manual exit from the loop in case the permission cannot be set up automatically.
- **If WhisPaste had to restart in the middle of the first-run setup** (e.g. to make a just-granted permission take effect), **setup began again from the very start**. It now resumes at the last step reached.
- **Occasional stray word fragments appended directly after an already complete transcript** have become rarer. Two previously unused tuning parameters of the local Whisper engine now suppress invented additions when audio fades at the end of a recording.

### Maintenance

- Internal build/Store tooling fixes: the Silero VAD model is now correctly code-signed (signed builds failed otherwise), the auto-update plugin stays reliably excluded from Mac App Store builds, and the App Store Connect automation now reliably assigns new builds to the correct version.

## 1.2.63

### Bug Fixes

- **A crash loop could occur if WhisPaste had once been installed under the old bundle ID.** The one-time data migration to the new app identifier wrote counters and timestamps internally as text instead of numbers. This led to a hard crash the next time the rating/support notice was checked. Affected installations heal themselves automatically at the next start, without a new data migration.
- **On macOS, the auto-paste permission sometimes had to be granted twice, and clicking the system notification did not lead directly to the matching setting.** Both are now more reliable: WhisPaste detects when an already granted permission only needs a restart to take effect, and offers the restart directly in both the notification and the hint text, instead of unnecessarily asking for the permission again.

## 1.2.62

### Bug Fixes

- **Once microphone access had been denied, the app got stuck in a dead end** ("Microphone access is missing", with no way to grant it). macOS never shows the system dialog again on its own after a denial. The message now leads directly to System Settings.
- **On macOS, every new build for the same version got the same internal build number** (a typo in the Info.plist configuration). As a result, App Store Connect could not reliably tell new builds apart from the previous one. Each build now gets its own, correctly sequential number again.

### Maintenance

- **In the (not-live) Mac App Store submission preparation, duplicate screenshots were sometimes stored.** A missing upload flag left old images in place instead of replacing them. Screenshots are now properly replaced on every update.
- Internal preparation for the next Microsoft Store update (no functional change to the app).

## 1.2.61

### Maintenance

- **The macOS app icon was not cropped to Apple's prescribed proportions** (too little margin around the motif). It is now correctly adjusted to the specification.
- **A second PowerShell error in the revised Microsoft Store upload from 1.2.60 has been fixed** (it affected only the internal release process, with no functional change to the app).

## 1.2.60

### Maintenance

- **The macOS build had been continuously broken since the last release** (it affected CI, the regular download build and the Store submission alike). A build script was missing its execute permission. Fixed; all three paths build cleanly again.
- **The revised Microsoft Store upload from 1.2.59 failed on its first real run** (a PowerShell compatibility error with freshly committed Store entries that had no open submission). Fixed.

## 1.2.59

### Maintenance

- **Store publishing automation revised** (affects only the deployment process, with no functional change to the app itself): the Microsoft Store package upload runs automatically again, and the purchase price for the (not-live) Mac App Store submission preparation is now set directly via the App Store Connect API instead of manually.

## 1.2.58

### New Features

- **The support notice is now timed more fairly and worded more honestly.** Instead of a single permanent dismissal, WhisPaste now remembers in stages when it last asked (90 days after a deliberate dismissal, 9 months after a click on the support link), and shows the notice at most three times in total. The text now openly names what the costs are for (Apple Developer Program, Microsoft Partner Center, hosting), without naming specific amounts.

### Bug Fixes

- **Windows wrongly reported a new version even though the current one was already installed.** A formatting difference between the app's own version number and the update check repeatedly prompted WhisPaste to reinstall the same version.
- **Failed model downloads showed only "null" instead of a real error message.** This affected both Whisper and Parakeet downloads. The message now states the actual cause.
- **A rare crash on quit via Cmd+Q or the Dock under macOS is fixed.** Only this one quit path was affected. Shutdown via the tray menu already worked cleanly.
- **"Launch at Startup" did not work at all on macOS**, although the toggle could be enabled. It is now implemented cleanly via the native macOS autostart system.
- **The "Add" button for custom replacement rules had unreadable text** (light turquoise on a turquoise background).
- **The Settings page no longer filled the full window width** like all other pages of the app. Fixed.
- **Numerous smaller accessibility and usability improvements:** better screen reader announcements for recording status and history entries, more elements reachable by keyboard, larger tap targets on small icon buttons, more consistent respect for the reduce-motion setting, and the floating overlay/button now stays within the visible screen area after a monitor is unplugged or re-plugged.

### Maintenance

- **macOS app identifier changed internally** (prerequisite for the planned Mac App Store submission). Existing settings and API keys are migrated automatically to the new identifier at the first start, without any user action.

## 1.2.57

### Bug Fixes

- **Minor fix in the download support window on the web page:** on macOS, the "Star on GitHub" entry appeared accidentally twice.

### Maintenance

- **Microsoft Store publishing workflow hardened.** A platform-specific error prevented price and store texts from being reliably applied during automated submission. This is fixed and hardened.

## 1.2.56

### Maintenance

- **Release housekeeping.** v1.2.54 and v1.2.55 were replaced by this release (identical feature set) — pure infrastructure cleanup with no effect on the app itself.

## 1.2.55

### Bug Fixes

- **The punctuation settings are now grouped more clearly**, and the punctuation priming setting got a clearer German label ("Satzzeichen anregen").

## 1.2.54

### New Features

- **Custom vocabulary now also works with OpenAI cloud transcription.** Until now, the vocabulary stored in settings (names, technical terms) only took effect with the local Whisper engine. It is now also passed to OpenAI's cloud transcription.
- **New "Strip punctuation" switch** reliably removes periods, commas and other punctuation marks from every transcript. Unlike the existing "Punctuation priming", this works the same for every engine and every cloud provider, not only for local Whisper. Numbers, decimal values and version numbers are left untouched.
- **A notice now appears automatically** when macOS reset the auto-paste permission during an update, with one click straight to the grant. You no longer have to look for the cause in settings first.

### Bug Fixes

- **The beta channel no longer falls behind stable.** If no new beta build had appeared for a while, the app wrongly showed "up to date" although newer stable versions were already available.

## 1.2.53

### Bug Fixes

- **A rare crash when quitting the app under macOS is fixed.** The local speech recognition did not always release its GPU resources in time before the app closed completely.
- **A hanging model load now reliably leads to an automatic switch to the CPU** instead of aborting the session with an unclear timeout. This affected rare cases where GPU initialization took unusually long.

## 1.2.52

### Bug Fixes

- **A crash at app start under Windows is fixed.** It affected local transcription via the new in-app Whisper engine and appeared as an immediate crash. The cause was a missing internal initialization step, not the system or the hardware.
- **GPU acceleration for local transcription is now reliably used.** It could previously fall back to the CPU permanently, even when a suitable GPU was present or the GPU was forced in settings, with noticeably slower transcriptions as a result.
- **Longer status texts in the floating overlay are no longer cut off.** The display now adjusts its width to the actual text length, instead of truncating long messages with "…".

## 1.2.51

### New Features

- **Parakeet: a second, significantly faster local speech recognition engine.** Alongside Whisper, NVIDIA Parakeet is now available as a selectable on-device engine. On CPU-only hardware it is many times faster than Whisper, with support for around 25 languages (incl. German). A noticeable gain, especially on older or weaker hardware.
- **The local Whisper engine now runs directly inside the app instead of as a separate background server.** No server program to download anymore, faster start, and a dedicated recovery path with automatic retry on GPU crashes or memory problems.
- **GPU acceleration is now detected from the real hardware** and the matching backend is chosen automatically (NVIDIA → CUDA, Apple → Metal, AMD/Intel → Vulkan, otherwise CPU).
- **Automatic updates.** WhisPaste now keeps itself up to date: signed, cryptographically verified updates on macOS (Sparkle) and Windows (WinSparkle, Ed25519), with no manual download. Anyone who has installed the app once automatically receives future versions.
- **The hotkey-to-text latency is now visible live in the analytics dashboard.** It is captured purely locally, without any transmission, as tangible evidence of how quickly the text actually arrives.
- **Settings can now be exported and imported as a file** (custom vocabulary, snippets, keyboard shortcuts). Handy for multiple devices, without any cloud or account.
- **A new test-recording step in the first-run setup wizard, which can be skipped at any time,** lets new users try hotkey → recording → text live once before getting started.
- **Punctuation is now set more reliably by default**, without a loss of speed. It can be switched off in settings if needed.
- **A subtle hint now shows the note and search syntax** (e.g. `tag:`, `korrektur:`, `#tag`) directly in history and voice notes.
- **An error sound is now correctly wired and audible** when pasting fails. It can be disabled in settings.
- **The feedback form now optionally accepts a contact email**, in case a follow-up is wanted. It is never prefilled and always optional.

### Bug Fixes

- **Crash reports correctly attributed.** Native stack traces now land in the correct Sentry release (`whispaste@…`), so crashes are reliably decoded and assigned to the correct build.
- **A switch to CPU processing is now clearly displayed** instead of happening silently in the background.
- **A paste blocked by privilege escalation under Windows is now clearly explained** instead of showing a generic error message.
- **Autostart no longer wrongly shows "enabled"** when registration with the operating system actually failed.
- **The overlay now stays reliably stable when switching the speech recognition engine.** A more robust handshake procedure with retry prevents stuck states.
- **Custom vocabulary is now reliably passed to the local Whisper engine.**

## 1.2.43

### Bug Fixes

- **Privacy and website links point to the correct address and language again.** The links in the app (About page) now lead to the German or English privacy policy at whispaste.de, depending on the language. Previously some of them led to an outdated address and went nowhere. The English privacy page of the website was also extended with the missing hosting and tracking notices, so German- and English-speaking visitors get the same information.

## 1.2.42

### Features

- **Push-to-talk and more reliable keyboard shortcuts on Windows.** Hold to talk, release to stop now works cleanly. AltGr and layout-specific keys are correctly recognized and no longer wrongly treated as Ctrl+Alt, regardless of which keyboard layout is active.
- **Redesigned recording overlay.** A subtle frosted-glass look, a pill that grows along with the current phase, and smooth transitions between recording, transcription and "Done". It looks identical across platforms and fits every color scheme.
- **Clear empty, loading and error states** in history, statistics and settings, instead of blank areas. You can always see what is happening.
- **Consistent keyboard and accessibility support.** A visible focus ring appears only during keyboard use, the sidebar and settings are fully keyboard-operable, and reduce motion is respected everywhere.
- **Calmer animations.** A dampened motion system replaces the earlier springy effects and follows the system reduce-motion setting.
- **More consistent typography.** WhisPaste now ships the Inter font for a consistent appearance on all platforms.
- **Transparent telemetry notice in onboarding.** The anonymous usage statistics, which can be switched off at any time, are explained on first start and can be disabled right there. The About page summarizes the key points.

### Bug Fixes

- **Recording no longer hangs on a quick stop.** A quick stop can no longer block the recording step, and no transcription ends in a timeout anymore.
- **The overlay stays reliably above all windows on Windows** and no longer slips behind other programs.
- **The waveform stays visible from the second recording onward** and is no longer cut off.
- **The overlay is drawn at full screen sharpness on Windows** instead of looking slightly blurred.
- **Resetting the settings (re-onboarding) now always runs through completely**, even if one sub-step fails.
- **No more rare crash on quit** while the history is still being saved.
- **A layout inaccuracy in the transcript editing toolbar is fixed.** The word count now yields cleanly instead of being clipped slightly at the edge.
- **The "Privacy policy" link on the About page works again.** It now points to the current privacy policy, depending on the language, instead of leading to an outdated address that went nowhere.

## 1.2.41

### Features

- **Anonymous, self-hosted usage statistics to guide development.** Active by default, and can be switched off at any time under Settings → Privacy. Cookie-free, without an account or device identifier, and never includes content (text, audio, history). Details are in the privacy policy.

### Bug Fixes

- **The local speech service can be downloaded reliably again on Windows with NVIDIA graphics.** WhisPaste now skips broken download entries, falls back cleanly to Vulkan or CPU when needed, and processes the manifest files delivered by GitHub robustly, instead of hanging with "Network error: unknown".

## 1.2.40

### Features

- **Settings are now searchable and fully keyboard-operable.** A search field at the top filters the sections live, jumps to the match and stays visible while scrolling. The entire interface works via keyboard and screen readers (sensible focus order, jump marks, read-out labels).
- **Settings tidied up and condensed.** Related switches are combined: the sound on/off toggle now sits in the volume slider, the autostart options are in a single dropdown, history retention is a preset (default/custom), and the overlay toggle sits together with its position. The language dropdown now shows the recognition languages in the interface language.
- **Live preview for the overlay and the record button directly in settings.** Both are shown at original size (1:1) and reactively, so a change looks exactly as it will later appear.
- **The recording display (overlay and button) was redesigned and is identical across platforms.** A shared design source is rendered natively on macOS, Windows and Linux: the same waveform with a scrolling history, the same appearance in every color scheme, and a correctly sized, cleanly positioned compact variant.
- **Automatic in-app updates on macOS.** WhisPaste can now update itself on macOS (atomic DMG replacement, with privilege escalation if needed). An ongoing recording postpones the installation until it is complete.
- **Comprehensive screen reader support.** Onboarding, history, the central controls, the About page, and the feedback and cloud sections now carry read-out labels. Non-interactive images, form fields and icon buttons are correctly annotated.

### Bug Fixes

- **A hidden overlay no longer catches mouse clicks.** An invisible overlay could previously still intercept clicks. When hiding (including the automatic hide after "Done"), the native window is now reliably removed from the screen instead of lying invisibly.
- **Dictation is no longer lost on a quick stop.** The stop paths (manual, automatic on silence, dead microphone) are consolidated. A dead microphone no longer aborts an already running transcription (that was silent data loss), and simultaneous stop calls now merge cleanly into a single run.
- **A held key combination fires exactly once.** The operating system's auto-repeat is intercepted, so a held-down hotkey does not fire multiple times.
- **No more double pasting on macOS.** If pasting already succeeded via CGEvent, the AppleScript fallback is no longer executed as well.
- **No more stutters on open caused by the model scan.** The check for existing speech models no longer runs blocking on the UI thread (especially on virtualized file systems), so the waveform and time display stay smooth.
- **A new recording can start immediately while the "Done" or error display is still running.** The trigger no longer reacts with a delay while the overlay is still visible.
- **The overlay keeps its set size when hiding** and reliably fades out after 2 seconds once "Done" is shown.
- **On a fresh install, history retention shows the default preset** instead of wrongly showing "Custom".
- **Linux packages run more reliably.** The Flatpak now starts on the GNOME runtime with bundled native libraries. The Snap build is produced under managed LXD and includes complete store metadata.

## 1.2.39

### Bug Fixes

- **All 99 Whisper languages work again, and automatic language detection now actually runs.** The Store review reported "only 4 languages work, Russian comes out as English". The cause was three stacked app-side restrictions. The shipped multilingual models can handle all 99 languages, but with "Auto-detect" the language was replaced by the UI language (so detection never ran), the language field was omitted during inference (the server and Deepgram silently fell back to English), and both the pre-flight check and the settings dropdown were hardcoded to en/de/fr/es. "Auto-detect" is now sent explicitly, Deepgram receives `detect_language=true`, and both the dropdown and the allowlist use the full language catalog.
- **Cloud transcription (Deepgram/OpenAI) now works on macOS.** The API key was accepted in settings, but every recording failed after about 100 ms with the generic error message. Cause: `flutter_secure_storage` wrote to the macOS data-protection keychain, which requires an entitlement that the non-sandboxed build does not carry. The key never reached the keychain, and the cloud transcribers always saw an empty key. Storage now uses the file-based login keychain, and cloud authentication errors are reported clearly.
- **Cloud providers can be used without a local speech model.** The pre-flight check wrongly also required the local `whisper-server` and a downloaded model for Deepgram/OpenAI, and the local server was started unconditionally, so pure cloud users could never start a recording. The cloud pre-flight check now verifies the configured API key (failing early instead of only after dictation) and skips starting the local server.
- **A damaged or too-small speech model now re-downloads automatically and silently.** On start, a faulty model file is now re-downloaded automatically, as already happens on a SHA mismatch, instead of only being deleted and pointing to settings.

### Features

- **Linux desktop support: the speech server for Linux x64 is now fetched automatically.** The shipped manifest now contains a real `linux/x64/cpu` entry (statically linked, runs on every glibc distribution). A Linux installation downloads, extracts and starts `whisper-server` via the existing self-download mechanism, so dictation works like on Windows/macOS. Linux packages are also available as Flatpak, Snap, AppImage and `.deb`.
- **New "Graphics Acceleration" settings section (Auto / On / Off).** A deliberate user choice now takes precedence over the speech service's automatic GPU/CPU selection.
- **Problematic older graphics cards fall back to the CPU before startup.** Known problematic GPUs (Kepler/Fermi, older AMD GCN) are proactively routed to the CPU path instead of falling back only after a crash. Unsuitable flash attention is actively disabled.
- **Gentler reaction to brief speech service hiccups.** A temporary blip in the liveness check no longer forces a full restart (limited retry with a grace period). A real hang still triggers exactly one restart.
- **Self-downloaded `whisper-server` binaries are verified by SHA-256.** On a mismatch the artifact is discarded and a clean error is reported, instead of starting a corrupted binary.
- **Dedicated empty states for the history filters (Favorites / Today / This Week).** An empty filter now shows a fitting hint, instead of giving the impression that the entire history has disappeared.
- **Orphaned `.tmp` fragments of aborted model downloads are cleaned up.** On start and after a completed download, old fragments are conservatively removed. Resumable downloads remain untouched.

## 1.2.38

### Bug Fixes

- **Dictation is no longer lost when a recording is stopped quickly again.** On stop, a write still in progress that was not awaited could leave the WAV header with zero sizes. The speech service rejected such a file with `HTTP 400 "Invalid request"`, and the transcription was lost (`FLUTTER_WHISPASTE-7X`). The recording pipeline now serializes writes and repairs faulty RIFF/data size fields before inference.
- **The GPU speech server no longer ends in an endless cuda↔vulkan loop, but reliably falls back to the CPU (older NVIDIA cards).** A Vulkan build installed via recovery was wrongly deleted as incompatible on a CUDA-optimal card, and the crashing cuda build was loaded again. Recovery exhausted itself without ever trying the CPU build (`FLUTTER_WHISPASTE-A0`). Compatibility now means "runs on this machine", not "optimal". Intentional downgrades remain in place.
- **The shipped CPU/BLAS fallback is no longer deleted on every start on Vulkan-optimal machines.** A DLL heuristic classified a CPU-floor build without `.server-info.json` (observed under MSIX) as incompatible and triggered the same delete → re-download → crash cycle. The heuristic now distinguishes CPU-floor builds from GPU builds.
- **Silence and background noise no longer insert placeholders into the text.** Tags such as `[Music]`, `[BLANK_AUDIO]` or `[Applause]` are removed before insertion or saving. A pure marker text is correctly treated as an empty transcription. Text dictated in brackets remains untouched.
- **Hints for a missing speech model or speech service are now clickable.** The previously passive hint toasts (download in settings) now carry an "Open Settings" action that jumps directly to the right section.
- **Unified "speech service" naming throughout the interface.** The previously mixed terms "speech engine", "speech module" and "speech service" now all read "speech service" (EN). The model step in onboarding correctly refers to the "speech model".
- **Duplicate heading removed in the "After transcription" section.** The action selection repeated the section title verbatim. It now has its own "Action" label.
- **Dead Apple Store rating link removed.** The rating path is now platform-appropriate (Windows Store link or GitHub star), without the structurally invalid `apps.apple.com` URL.

### Features

- **New installation channels: Scoop, winget and Homebrew.** In addition to the installer and the Microsoft Store variant, package manager manifests for Scoop, winget (Windows) and Homebrew cask (macOS) are now available. The download page documents the Scoop installation.
- **The standalone diagnostic tool now lists all installation data paths side by side.** When an EXE installation and one or more MSIX `LocalCache` installations coexist, the report shows every data path found, with its variant label, instead of silently picking one.
- **One-time, idempotent data migration for the bundle ID change.** API keys and settings are carried over once at the first start, without overwriting existing data.
- **Onboarding adapts to auto-paste support.** On builds without automatic pasting, the non-applicable auto-paste/accessibility steps are omitted.

## 1.2.37

### Bug Fixes

- **The speech service now also starts reliably in the Microsoft Store variant (MSIX). The speech model is found instead of failing with "cannot be opened" (older NVIDIA cards, e.g. GeForce GTX 650).** In the packaged Store variant, WhisPaste writes the model and `whisper-server` to `%APPDATA%\WhisPaste\models\stt`. The MSIX runtime transparently redirects these writes into the package-private `LocalCache`. However, the **`whisper-server` started as a child process does not inherit this redirection**. It resolves the same path against the **non-virtualized, empty** real roaming directory and aborts with exit code 3 (`ggml_backend_load_best: search path … does not exist` / `failed to open`), even though the app sees the file as present and SHA-256-verified (`FLUTTER_WHISPASTE-A0`). New: the paths passed to the child process (model argument, start path and working directory) are rewritten before launch to the **physical** package path `%LOCALAPPDATA%\Packages\<package name>\LocalCache\Roaming\WhisPaste`, so parent and child process resolve the same file. Storage remains unchanged (no re-download), and the rewriting has no effect outside Windows/MSIX. The GTX 650 odyssey of v1.2.32–v1.2.36 was therefore ultimately caused not by GPU or DLL issues, but by pure MSIX path virtualization.

### Features

- **New cross-platform diagnostic tool (native Dart) replaces the old script-based tool.** The standalone speech service report is now generated from a shared pure-Dart core library: as a `dart compile exe` binary on Windows, and as `.app`/DMG on macOS. Previously it came from a Windows-only PowerShell script. The report additionally covers hardware, permission, AV/quarantine and settings probes, a DLL dependency analysis with fingerprint mapping plus an automatic assessment, and runs through an end-to-end privacy sanitizer (paths/usernames). Delivery works without a backend: the report is shown in the file manager and a prefilled email is opened.

## 1.2.36

### Bug Fixes

- **The GPU speech server now falls back to the CPU before startup if a required system library is missing (older NVIDIA cards, e.g. GeForce GTX 650).** The GPU builds of `whisper-server` link the GGML backends statically, but at *load time* they import a system loader that the graphics driver provides: the Vulkan build needs `vulkan-1.dll`, the CUDA build the CUDA runtime. Neither is in the ZIP. On a machine whose driver never installed the loader, and which the variant router sends to Vulkan (Kepler GTX 6xx), the process therefore aborts with `STATUS_DLL_NOT_FOUND` (`0xC0000135`) **before `main()` runs**. `--no-gpu` cannot prevent this, because the OS loader resolves the import before the flag is read (`FLUTTER_WHISPASTE-A0`). New: a pre-launch gate checks the loader DLLs of the installed variant on Windows (binary folder + `System32`, analogous to the VC++ runtime check). A missing loader is handed to `ServerBinaryRecovery`, which switches to the dependency-free CPU build **before** the crash, instead of recovering only after the fact via the exit classifier. A Windows smoke test confirmed that the working directory was never the blocker (the model loads even with `cwd=System32`).

### Features

- **In-app diagnostics ("Copy Debug Info") now deliver a complete speech service dump, including a real model-load test.** The dump captures the STT failure state and actually probes the model load, instead of only collecting metadata. This is the most important information for diagnosing a startup error remotely.
- **Standalone speech service diagnostic tools for Windows and macOS, attached to every release.** Users without a working app can create a debug report: on Windows as a standalone `.exe` (plus an AV-safe script bundle), on macOS as a double-clickable `.command` in the DMG.
- **Diagnostic guide on the download page** walks through creating and sharing a speech service report step by step.

## 1.2.35

### Bug Fixes

- **Hanging GPU speech servers now fall back to the CPU instead of ending in a dead end (older NVIDIA/AMD cards, e.g. GeForce GTX 650).** The v1.2.32–v1.2.34 fixes tied the CPU fallback to *process exit codes* (`gpuFatal`/`heapCorruption`/abnormal exit). On a Kepler card, however, the Vulkan build does not necessarily crash. It **initializes fully (model loaded, all compute buffers allocated) and then makes no further progress**. A hang produces no exit code, so none of the exit-code branches triggered. The `SttServerStateNotifier` went through the heartbeat timeout (`stt_heartbeat_timeout`) or the startup deadline (`stt_startup_deadline`) directly into the `error` state, and the working CPU build was never tried (`FLUTTER_WHISPASTE-9W`). New: both stall paths now trigger the one-time CPU fallback, like the exit-code branches, and restart the speech server immediately in CPU mode. This is guarded by `gpu.hasGpu` (on pure CPU machines the error correctly remains, without a pointless restart) and by `_gpuFallbackActive` against loops. This finally covers the hang case that the earlier exit-code fixes left open for the GTX 650.
- **Expected network errors during update checks and server/model downloads no longer create Sentry events.** The update check, the manifest loader and the download client run best-effort against third-party endpoints whose errors are expected and already handled cleanly (error state, failover chain, or their own fingerprinted captures). The `addSentry()` interceptor nevertheless captured every 5xx automatically as a Sentry event (default range 500–599). That was useless noise that burned the free-tier quota and reported download errors twice, contrary to the documented intent (`FLUTTER_WHISPASTE-72`). `captureFailedRequests` is now disabled on these clients. Tracing spans and breadcrumbs are retained.

## 1.2.34

### Bug Fixes

- **On older NVIDIA cards (e.g. GeForce GTX 650), the app now clearly states what is missing instead of ending in a dead end.** The v1.2.33 fix ended the "Incompatible whisper-server" delete loop, and the recovery now stays permanently on the CPU build. This exposed a follow-up case: the shipped CPU build is the upstream asset `whisper-blas-bin-x64`, whose binaries link dynamically against the Microsoft Visual C++ runtime. `whisper-server.exe` needs `MSVCP140`/`VCRUNTIME140`/`VCRUNTIME140_1`, and `ggml-cpu.dll` additionally needs the OpenMP runtime `VCOMP140.DLL`. None of these is in the ZIP. They come from the Visual C++ Redistributable, which is missing on many older or fresh Windows installations (especially the OpenMP DLL). As a result, the CPU server aborts with `STATUS_DLL_NOT_FOUND` (`0xC0000135`), recovery is exhausted, and the user is stuck (`FLUTTER_WHISPASTE-A0`). New: `ServerBinaryRecovery` recognizes a `dllMissing` abort of the CPU floor as a missing VC++ runtime and shows an **actionable toast** with an "Install" button. It opens the download of the **Visual C++ Redistributable (x64)**, instead of the useless "restart the app" message. The Sentry event now carries a `vc_runtime_missing` flag for unambiguous triage.
- **The CPU fallback will in future ship self-contained (preparation).** A new CI job `build-cpu-windows` repackages the upstream BLAS asset as `whisper-server-cpu-x64.zip` and bundles the four required runtime DLLs (`vcomp140`, `vcruntime140`, `vcruntime140_1`, `msvcp140`) app-locally. The manifest then points the `cpu` entry to this own artifact instead of the bare upstream ZIP. It takes effect after the next `build-whisper-server` run that regenerates the manifest. After that, the CPU floor heals on every machine without a separate redistributable installation.

## 1.2.33

### Bug Fixes

- **The speech server now stays permanently on the CPU variant when the GPU builds do not start (older NVIDIA cards, e.g. GeForce GTX 650).** The v1.2.32 fix corrected the backend routing, but one residual case remained. On a Kepler card even the Vulkan build aborts at model load (exit code `3`), whereupon `ServerBinaryRecovery` correctly falls back to the **CPU build** and writes `backend=cpu` into `.server-info.json`. At the next start, however, the proactive compatibility check reported "installed=`cpu`, but GPU needs `vulkan`", **deleted exactly that one working binary**, and threw "Incompatible whisper-server for your GPU". This was an endless loop of recovery → CPU → delete → re-download → crash. It could not be eliminated even by reinstalling and completing the full onboarding (`FLUTTER_WHISPASTE-80`). The cause was a conflict between two subsystems: recovery deliberately chooses the CPU as the universal fallback, but the proactive check treated "CPU on a GPU-capable machine" as a misconfiguration. New: `isServerBinaryCompatible` treats a CPU build as **universally compatible**. It runs on any hardware and is the intentional recovery end state, so it is no longer deleted. The loop is thus definitively broken. Affected devices transcribe on the CPU (slower, but functional). Anyone who wants to try GPU acceleration again can re-download the speech server in settings.
- **A genuine hardware or driver change now leads to a silent self-heal instead of a dead end.** If the proactive check finds a truly unsuitable GPU binary (e.g. the STT folder was moved to a machine with a different GPU vendor), it now downloads the correct variant in the background (`invalidateServerBinary`), instead of aborting with "re-download in Settings" and creating a Sentry event. If the re-downloaded GPU build fails again, the now-permanent CPU recovery applies.

## 1.2.32

### Bug Fixes

- **The speech server starts again on older NVIDIA cards (Kepler, e.g. GeForce GTX 650).** The backend selection previously treated every NVIDIA card with an existing `nvcuda.dll` as CUDA-optimal and loaded the `cuda12` build. But CUDA 12 has completely dropped Fermi (sm_2x) and Kepler (sm_3x) support. On a GTX 6xx/7xx, `whisper-server` therefore aborts during CUDA init: in practice immediately with exit code `-1` and empty stderr (`FLUTTER_WHISPASTE-6X`/`-39`), or as a model-load error with exit `3` (`-6V`/`-6W`). Worse: even when recovery fell back to the Vulkan build, the proactive compatibility check reported at the next start that the Vulkan build was ≠ `optimalBackend` (`cuda`), deleted it and forced `cuda12` again. This was an endless loop, surfacing as "Incompatible whisper-server for your GPU" (`FLUTTER_WHISPASTE-80`). New: a `GpuInfo.supportsCuda12` heuristic (analogous to `supportsFlashAttn`) recognizes Kepler/Fermi cards by their model name and routes them to the Vulkan build. `optimalBackend`, the `serverAssetPatterns` fallback and the manifest `WhisperBinarySelector` now respect this consistently. This breaks the loop, and the self-heal download immediately fetches the working variant.
- **An abnormal server crash now falls back to the CPU automatically.** An unclassified abort with a negative exit code (a raw Windows DWORD such as `-1`, or a POSIX signal kill) during a GPU start used to be a dead-end `error`, because `SttGpuFallbackPolicy` only covered the known NTSTATUS GPU fatals. Exactly this form hits old GPUs whose GPU runtime never initializes (`FLUTTER_WHISPASTE-6X`/`-39`). The `other` path in the `SttServerStateNotifier` now activates the CPU fallback: once, guarded by `_gpuFallbackActive` against loops, and only for a negative exit code. It mirrors the `gpuFatal`/`heapCorruption` branches. A clean positive exit (e.g. `99`) remains a deliberate server exit and still surfaces as an error.

## 1.2.31

### Features

- **The microphone step in onboarding now shows live whether the selected device can hear you.** Instead of merely querying the TCC permission, the new step runs a short test recording, measures the real input level, and classifies the device as "works", "too quiet" or "nothing to hear". The dropdown selection passes through the same device pool as the actual recorder, so what is chosen in onboarding is also the device that records later. This works hand in hand with the second part: `AVAudioEngine.inputNode.auAudioUnit.setDeviceID()` is silently ignored under macOS 15/26. As a result, the user's selection never reached the recorder, and every recording fell back to the system default (often a Bluetooth headset). A direct switch to `AVCaptureSession` would have blocked the HAL exclusively and suppressed the SoLoud recording chimes. The solution follows the Logic/Audacity/OBS approach: a new `AudioRoutingHost` Swift bridge switches the CoreAudio default input device to the user's choice immediately before each recording, and restores the original value when stopping. A settle poll on the default-UID property ensures that AVAudioEngine binds to a device that is ready for live input, rather than one still waking up from power save.
- **The auto-paste onboarding step has been completely reworked to one call to action per phase.** The macOS step previously rendered up to four cards at once (status, polling hint, TCC mismatch banner, repair panel), in tech-heavy wording (accessibility permission, TCC cache, repair). The in-app self-test with a `TextField` was also unreliable, because Flutter did not stably receive the synthesized ⌘V from its own process. The "proof it works" step sometimes reported success while the demo field stayed empty. The new phase state machine (`checking / granted / intro / waiting / troubleshoot`) is derived from the existing `PasteCapabilityState` and renders exactly one primary action per phase. The TCC mismatch banner gets an embedded "Restart WhisPaste" call to action, which starts a detached shell helper via a new `restart` hook on the app lifecycle method channel. The helper waits for the current process to exit and reopens the bundle, so macOS evaluates the Accessibility trust against a fresh PID instead of the dead parent process. The DE/EN/HE strings were rewritten to a friendlier tone for the write flow, including the "Reset entry" button. The `diagnosticPaste` may now test against the real active app: the self-paste guard is gone, and the pasteboard restore window was widened to 300 ms.

### Bug Fixes

- **The speech server download in onboarding works reliably again.** Up to v1.2.30, the `WhisperServerDownloader` queried the GitHub Releases API with `per_page=20` and searched for the `whisper-server-*` tag via a substring match in the asset list. As soon as enough of the app's own `v1.2.x` releases had accumulated, the whisper-server tag dropped off page 1. The lookup returned `null`, and the user in onboarding saw only the meaningless "Could not download whisper-server.". The new path is manifest-driven: `assets/whisper-server-manifest.json` is the sole source of truth (schema_version, whisper_server_tag, whisper_cpp_release, plus one entry per platform/arch/backend binary). A `WhisperServerManifestLoader` runs through a three-step failover chain (raw.githubusercontent.com → release asset URL from the bundled tag → the bundled asset), so onboarding stays usable offline. A deterministic `WhisperBinarySelector` performs the platform+arch+vendor lookup. Gaps (e.g. macOS x64, Linux) are reported with a specific reason instead of crashing generically. `build-whisper-server.yml` regenerates the manifest from the freshly uploaded release assets, attaches it to the release and commits it to `main`, so the raw URL stays stable and current.

### Stability (internal)

- **Windows CI flake in the recovery toast finally fixed.** The `stt_exit_classifier_test` run was intermittently red on Windows with "failed after test completion". The test bodies passed green, but about 2 s later an async leak fired into the already disposed Riverpod container. The cause was `_attemptRecovery` in `SttServerStateNotifier`, which called `ref.read(recoveryToastNotifierProvider.notifier)` after several `await`s without checking the `ref.mounted` status. The parallel `ref.invalidate` call in `_restartAfterRecovery` already had the guard. The toast push was the last unguarded spot. The push is now wrapped in the same `if (ref.mounted)`. Production behavior is unchanged (a disposed container means the UI is gone anyway, so suppressing the toast is correct), but the post-completion callback no longer touches a dead scope.
- **Widget tests immunized against ARB rewording.** The 23 auto-paste failures that broke CI in v1.2.30 were caused by tests that hardcoded UI labels as literal strings (`'Allow now'`, `'Reset entry'`, `'Skip — disable Auto-Paste'`, …). Every ARB rewording silently broke the suite. Sixteen test files now use `find.text(l10n.<key>)` lookups via a loaded `L10n` snapshot and explicitly pin their locale to `en` (or `de`/`en` pairs for the multi-locale toast tests). Neither the CI runner's default locale nor ARB rewordings can silently break the tests anymore. A key rename in the ARB now surfaces as a compile error, while a value rewording stays invisible. Test data (sample entry titles, device names, harness strings such as `'Open picker'`) intentionally remains literal, because it is never run through localization.

## 1.2.30

### Stability (internal)

- **Windows CI flake in the STT notifier fixed for good.** Two places in `SttServerStateNotifier` (`_start` and `_handleModelLoadFailure`) called `hw.detectGpu()` directly, thereby bypassing the Riverpod override for `gpuInfoProvider` that all affected tests had already set. On the Windows runner, this ran the real WMI/PowerShell GPU probes for every test run, with two consequences. First, a delayed `gpuDetectionFailed` Sentry event leaked into the capture count assertions of `stt_inference_capture_test`, because the detector from the "windows-vendor-unclassified" path still fired after `_capturedEvents.clear()`. Second, the recovery test ran into its 200 ms timing window, because `clearGpuCache()` plus re-detection no longer left the second `runner.start()` spawn enough time. Both call sites now go through `await ref.read(hw.gpuInfoProvider.future)` (same pattern as the benchmark path at line 767), and `_restartAfterRecovery` invalidates the provider in parallel with the module-internal cache. Production behavior is unchanged (same caching, same re-detection after recovery), but on the Windows runner the tests now deterministically see their fake `GpuInfo` instead of the real hardware probes.

## 1.2.29

### Stability (internal)

- **Hardware-specific crashes can now be diagnosed in Sentry.** Four paths that previously either were not reported at all or ended up in the `appLoggerAutoEscalated` catch-all, producing useless generic events per crash, now have their own fingerprints and carry the full hardware context: `sttCudaOom` (CUDA OOM in whisper-server, with GPU name, VRAM, model plus target VRAM, stderr tail), `sttInferenceConnectionLost` (SocketException/ClientException during inference, with model, port, WAV size, GPU mode), `sttStartupDeadline` (absolute wall-clock deadline in the startup loop, catching the long-load form that the heartbeat window alone cannot end), and `gpuDetectionFailed` (the GPU probes return nothing, typically due to corporate AV or blocked WMI). The GPU detection capture has a once-per-session guard with re-arming via `clearGpuCache`, so Sentry sees repeated failures on a recovery restart instead of being starved by the initial detection.
- **The architecture tag in Sentry now shows the real CPU architecture.** The old `_currentArch()` was a compile-time constant (`0x7FFFFFFFFFFFFFFF > 0`) that returned `'x64'` on every platform, including Apple Silicon. The new `currentArchTag()`, based on `Abi.current()` from `dart:ffi`, correctly returns `arm64` / `x64` / `x86` / `arm` / `riscv64` / `riscv32`. This finally makes hardware cluster filters in Sentry usable. It affects both the `dist` field and the `arch` scope tag.
- **Dedup migration of the hot STT paths.** Eight `_log.error` call sites in `SttServerStateNotifier` (GPU fatal capture, heap corruption capture, other-exit capture, recovery exhausted, ABI mismatch path, model corruption, sub-optimal binary detect check) each sat immediately before or after an explicit `captureError`. The additional auto-escalation sent the same incident to Sentry twice, once with the correct fingerprint and once in the catch-all. These call sites are now downgraded to `_log.warning`. Model corruption, previously only logged via `_log.error`, gets its own `sttModelCorrupted` capture with file size and model ID. On average, this halves the Sentry event volume per hard speech-service failure without losing diagnostic information.
- **`SttStartupHeartbeatConfig` as a value object instead of a record type.** The provider type is now a class with defaults (`window: 60 s`, `maxMissedWindows: 3`, `overallDeadline: 180 s`), so the added wall-clock cap does not break every test. All 28 test sites that used the former `({Duration window, int maxMissedWindows})` record literal were migrated 1:1 to the constructor.

## 1.2.28

### Bug Fixes

- **Feedback works again: schema drift in the Supabase backend fixed.** Between April 21 and May 27, every feedback submission failed server-side. The `locale` column was missing from the production schema, and the `enforce_feedback_defaults` trigger accessed a `user_agent` field that never existed. As a result, PostgREST rejected every INSERT with HTTP 400 before the RLS check even ran. The pending migrations (`20260418_add_feedback_locale`, `20260421_fix_security_advisor_findings`, `20260512_cleanup_edge_function_artifacts`, `20260513_cleanup_legacy_artifacts`) are now deployed. Feedback from already installed clients of versions 1.2.0+ gets through again immediately, without users needing an app update. Verified end-to-end with a real client payload: HTTP 201, all server-enforced fields (id, received_at, status, ip_hash from x-forwarded-for) correctly filled, RLS constraints and device/IP rate limits still effective.

### Stability (internal)

- **Server errors in the feedback path now actively escalate to Sentry.** Previously, `FeedbackSubmissionService` reported a backend problem only as a breadcrumb with `result: server_error`. Breadcrumbs disappear with the session unless the run also crashes. This is how the five-week schema drift could pass unnoticed, even though every submit produced an HTTP 400. `FeedbackServerError` now additionally triggers `Sentry.captureMessage('feedback_server_error', warning)` with the status code and the response body truncated to 500 characters, as a structured `feedback_response` context. Rate-limit, network and not-configured paths deliberately remain non-escalated, so user-driven behavior does not clutter the Sentry inbox. The deprecated `scope.setExtra` API was migrated to `scope.setContexts` at the same time (sentry_flutter 9.x).
- **Supabase migration history aligned with the remote schema that was actually applied.** Two manual SQL-editor sessions on May 3 had left `schema_migrations` entries with full second-precision timestamps (`20260503093151`, `20260503102718`), while the repo files only carried the day prefix (`20260503_…`). `supabase migration list` flagged the remote rows as orphans, and `db push` aborted with "Remote migration versions not found in local migrations directory". The files are now renamed to the full timestamps, and the history is reconciled without a destructive `migration repair --status reverted`.

## 1.2.27

### Features

- **Concrete toasts instead of "Something went wrong" for unusable recordings.** Obviously non-transcribable requests (empty WAV, broken header, unsupported language, overly long custom vocabulary) are now detected before the POST to the speech server and rejected with a matching plain-language hint. The user sees a specific message (e.g. that no audio was recorded, or that the language is not supported) instead of waiting for a speech server round trip plus a generic error message. Sentry now records these cases only as breadcrumbs, no longer as crash events.

### Bug Fixes

- **Duplicate crash reports for failed speech server responses eliminated.** Faulty inference responses (4xx/5xx from the local whisper-server) were previously sent to Sentry both via the explicit `captureError` path and via `_log.error` auto-escalation. Each inference error therefore produced two events in two different issue groups. The orchestrator now logs this path as a warning, and the central capture (with a stable fingerprint per status code plus a PII-sanitized body) sits directly in the STT notifier. 5xx responses also no longer pull the ServerBinary recovery into the path. That recovery was meant for crash exit codes, not for HTTP error responses. As a result, the previous Sentry issue scatter per inference error collapses to exactly one group per HTTP status code.

### Stability (internal)

- **Pre-flight validator and HTTP classifier for the inference pipeline.** A new `InferenceRequestValidator` deterministically checks every recording (empty bytes, then invalid WAV header, then unsupported language, then overly long prompt) against a sealed result class. A new `InferenceErrorClassifier` maps whisper-server HTTP responses to the central fingerprint table (400 / 413 / 415 / 5xx / unknown), with a PII-sanitized body (Unix, Windows and UNC paths → `<path>`) and six request-context extras. Both are pure, dependency-free value classes, throw no exceptions, and together with the notifier integration are covered by 1,229 new lines of tests.

### Dependencies

- **App stack patches:** `record` 6.2.0 → 6.2.1 plus the five platform companions (`record_android`, `record_ios`, `record_linux`, `record_macos`, `record_platform_interface`); `flutter_secure_storage` 10.2.0 → 10.3.0 (+ darwin/linux companions); `lucide_icons_flutter` 3.1.14+1 → 3.1.14+2; six transitive Dart packages (`built_value`, `url_launcher_android`/`_web`, `vector_graphics`(`_compiler`), `vm_service`). All bumps are pure patch/build updates with no API changes. The full test suite (1,775) is green, and the macOS debug build is green.
- **Website stack patches:** `astro` 6.3.3 → 6.3.8, `@astrojs/sitemap` 3.7.2 → 3.7.3, `@sentry/astro` 10.53.1 → 10.54.0 (removes 42 OTel auto-instrumentation packages from the build, positive for the free tier since it is a static marketing site), `dompurify` 3.4.5 → 3.4.6, `vitest` 4.1.6 → 4.1.7 (+ seven `@vitest/*` companions), `@typescript-eslint/eslint-plugin` and `parser` 8.59.3 → 8.60.0, `@playwright/test` 1.58.2 → 1.60.0. Website gate (tsc, eslint, vitest, build, Playwright) is green.

## 1.2.26

### Bug Fixes

- **CI build green again: `sqlite3` version explicitly pinned.** The v1.2.25 build ran cleanly locally, but the CI runner resolved `sqlite3` to an older major version (2.9.4 instead of 3.3.1). `sentry_drift 9.20.0` carries an outdated `sqlite3: ^2.1.0` constraint that collides with the `sqlite3: ^3.1.5` requirement of `drift 2.33.0`. Locally, the checked-in lock file kept 3.3.1 stable. On CI the resolver bypassed the lock and fell to 2.9.4, whose `SqliteException` has a different constructor, which broke the coordinator tests during `flutter analyze`. `dependency_overrides: { sqlite3: ^3.3.0 }` now forces both sides onto the same major version. This is pure build hygiene, with no behavior change in the app itself compared to 1.2.25.

## 1.2.25

### Features

- **The speech service now recovers by itself after crashes.** If the whisper-server crashes with a DLL, ABI or GPU error, the app now automatically falls back one level (CUDA 12 → Vulkan → CPU on Windows, Metal → CPU on macOS), downloads the matching variant, validates it and restarts the service. One attempt per variant is allowed per recording session, which rules out endless loops. Only when all levels fail does the user see a toast. Otherwise the next recording simply continues. On the final error level there is now an actionable "Open settings" toast that navigates directly to the reset section.

- **HTTP downloads no longer hang unnoticed.** A 30-second stall detector monitors the byte flow during model and server binary downloads. If the stream freezes (no progress, but no abort either, the typical bad-WLAN case), the app cleanly cancels the attempt and tries the next source. Previously the onboarding download could stand still for hours in the worst case without the UI noticing. In addition, the raw Dio errors are now translated into readable messages instead of stack-trace fragments.

- **Error toasts now have a useful action.** Six typical error sites now show a button for a direct fix instead of the generic "Something went wrong" toast: "Open settings" when speech service recovery is exhausted, "Try again" when a server download fails, "Copy diagnostics" for history write errors, "Quit app" for factory reset errors, and opening the Accessibility permission on the macOS auto-paste path. Where previously only a terse hint stood, there is now one click to fix the problem.

- **Factory reset no longer hangs or freezes the UI.** The reset flow now waits for the speech service to actually stop (PID file polling, 10-second timeout, hard kill as fallback) instead of a blind 800 ms sleep. Deleting several GB of models runs in a separate isolate, so the UI stays smooth. A modal progress indicator shows the individual phases ("Stopping voice service…", "Deleting voice models…"), so the user sees that something is happening. On error, the phase is named and reported to Sentry once, with no more duplicate reports.

### Bug Fixes

- **GPU detection no longer blocks onboarding.** The parallel `wmic` / PowerShell probes on Windows now have an 8-second timeout per probe and run as a race instead of serially. If detection fails completely (e.g. a blocked WMI interface or a missing DLL), the app now explicitly falls back to CPU mode and shows a friendly hint that GPU acceleration is unavailable and the app uses the CPU. Previously it wrongly marked the system as incompatible and blocked onboarding.

- **Duplicate crash reports for a failed server download eliminated.** The final error log of the model downloader was sent to Sentry both via auto-escalation and via the explicit `captureError` call, so each failed download produced two events in two different issue groups. The redundant log escalation is now a warning, so only the explicit, correctly fingerprinted capture call reports the event.

### Stability (internal)

- **History writes are now serialized.** All twelve write methods of the local SQLite database go through a single lock and retry on `SQLITE_BUSY` with `[50, 100, 200]` ms backoff before giving up. This eliminates most of the previous "Something went wrong" toasts during parallel writes (e.g. a recording finishes while the user deletes in the history tab), and the Sentry cluster WP-7B…7M collapses into a single signal.

- **Central crash fingerprint inventory.** All Sentry captures now mandatorily use fingerprints from a central inventory list. Thematically related errors fall into one issue group cleanly, and the free-tier quota is not burned by generic `Something went wrong` events. Update-check network errors no longer escalate to Sentry, but remain as breadcrumbs.

## 1.2.24

### Features

- **Microphone-volume slider is back — and it actually works this time**. The slider that was removed in v1.2.23 (because it had been dead code) returns as a real control. Behind the scenes the recording path was rebuilt: audio now flows through a PCM stream pipeline that splits in-process into the WAV writer and the level meter, with an optional gain multiplier inserted whenever the slider sits anywhere other than 100 %. At 100 % nothing changes (library autoGain still acts as before, default recordings sound the same as in v1.2.23); above 100 % the user gain takes over completely and library autoGain steps aside, so the slider's effect is predictable and audible. Range is 0–300 % in 5 % steps; 0 % records silence, 200 % is roughly twice as loud, and mid-recording slider movement is deliberately ignored — the gain captured at recording start governs the whole take.

- **Clipping warning surfaces in the settings**. When the gain is pushed high enough that PCM samples hit the 16-bit ceiling, the new pipeline counts those clipped samples per recording. A subtle banner below the gain slider lights up after a recording with clipping ("Last recording had clipping — reduce gain?") so the cause of a bad transcription is visible instead of mysterious. Dismissing the banner clears the warning until the next clipping event; a clean recording also clears it automatically. No modal, no sound, no OS notification — the banner sits passively in the place you would go to react to it.

## 1.2.23

### Bug Fixes

- **Maximum recording duration setting is now respected**. The recording safety guard counted amplitude samples to enforce `maxRecordDuration`, `deadMicTimeout` and `autoStopSilence`, but used the wrong sample rate — it expected 10 Hz while the audio service emits at 25 Hz (one sample every 40 ms). All three guards therefore fired 2.5× too early: a user setting "2:30" got cut off at ~60 s, dead-mic kicked in at 1.2 s instead of 3 s, and the 90 % duration-warning sound played at ~36 % of the configured limit. The orchestrator now passes the real rate to the guard, and the guard's `samplesPerSecond` knob has been promoted to a required parameter so the mismatch cannot silently re-appear. The orchestrator behavior-snapshot tests, which had calibrated against the buggy rate and locked the bug in as spec, have been re-calibrated.

- **Microphone-volume slider removed**. The slider in Audio Input was non-functional — the value was persisted but no code path in the recording pipeline applied it. The `record` plugin has no gain parameter and no PCM multiplication ran on the stream, so changing the slider had zero effect on the captured audio. Rather than ship a fix-by-implementation that would have widened this release's scope, the dead slider has been removed; if true input-gain control is wanted later it returns as its own feature.

- **"Show notifications" preference is now honoured**. The Interface toggle was persisted but never consulted — paste-blocked and paste-failed alerts fired through `SystemAttentionService` regardless of the setting. The native notification path now checks the preference and stays silent when the user has opted out. The dock-bounce / taskbar-flash fallback stays active either way; that is the layer that surfaces problems when the main window is hidden.

## 1.2.22

### Bug Fixes

- **Auto-Paste onboarding step removed on Windows**. First-run testing revealed that the diagnostic Test-Paste sub-step was reading as "press a hotkey" — users tried to trigger their dictation shortcut instead of clicking the in-step button, then got stuck because Next stayed gated. Since Windows needs no extra permission for `SendInput`-style paste in the 99 % case, the step delivered no real value and the UIPI/UAC edge stays surfaced through the Settings paste capability indicator. Windows now follows Linux's lead and skips the step entirely, taking the onboarding from five screens to four. macOS keeps the full flow because the TCC grant + verify is the actual user task there.

- **STT spawn and exit failures are now visible in Sentry**. The whisper-server lifecycle had several failure modes that only ended up in local logs (`_fail()` into the in-process state machine) while Sentry got either nothing or a one-line message. That made FLUTTER_WHISPASTE-4P-class incidents ("exited before becoming ready") undiagnosable without direct access to a user's machine. The notifier now ships a structured `captureError` for: spawn `ProcessException` (binary path, args, errno), heartbeat timeout (stderr tail + args + binary), early process exit on the unclassified path, and the generic `SttExitKind.other` exit code now carries the stderr tail, args, model id and GPU mode in extras (the message-only capture was the shape behind FLUTTER_WHISPASTE-6X). A new `stt.stderr` breadcrumb category mirrors stderr lines that look like errors so any later event in the same session inherits the signal, not just the dedicated STT captures.

## 1.2.21

### Features

- **Onboarding gains a dedicated Auto-Paste step**. New users now hit a guided `AutoPasteStep` before reaching the Ready screen. On macOS it triggers the Accessibility prompt, polls TCC state via a `PollingPhase` controller, surfaces a "Waiting for permission…" hint card while the System Settings sheet is open, exposes a lazy "Repair permissions" button (`tccutil reset Accessibility + AppleEvents`) that only appears once the user has had a chance to grant manually, and shows a sharper TCC-mismatch banner with a restart hint when the bundle ID granted in TCC no longer matches the running app. On Windows the same step runs a verify branch that detects the UIPI edge case (elevated foreground window blocks `SendInput`) and skips cleanly with a Windows-specific explanation. The step counter at the top of the wizard is now dynamic, so users on `clipboardOnly` mode (where the Auto-Paste step is skipped) no longer see misleading "Step 3 of 4" labels. A new diagnostic-paste endpoint backs a **Test-Paste sub-step** that lets the user verify the paste path end-to-end without recording first.

- **Hotkey conflict detection in `ReadyStep`**. The Ready screen now checks whether the configured global hotkey is already claimed by another running app or by the OS before the user hits Start. If a conflict is detected, the step blocks the Start CTA and points the user back to the Hotkey step instead of letting them finish onboarding into a broken state.

- **Dynamic language selector in `WelcomeStep`**. The welcome screen picks up the user's OS locale on first paint and proposes it as the default transcription language. The old static pill-row selector has been replaced by a shared `LanguageSelector` dropdown that scales to the full Whisper language catalog without overflowing.

- **`ReadyStep` reacts to `afterTranscriptionAction`**. The "What happens after recording?" preview on step 3 now updates live when the user changes the after-transcription mode (`copy` / `paste` / `clipboardAndPaste`) elsewhere in onboarding, so the preview text always matches the active mode.

- **Status-bar Auto-Paste-Off hint**. Users who skip the Auto-Paste onboarding step now see a one-time hint in the status bar explaining that Auto-Paste is off and how to enable it later, so the skipped path is recoverable without the user having to remember the setting exists.

- **Soft release-out on the floating overlay when recording ends**. The waveform now animates out gracefully when the overlay transitions from `recording` to `transcribing`, instead of snapping flat. The new `WaveformPipeline` drives a ring-buffer of bar heights with configurable attack/release smoothing, so the visualisation tracks speech energy faithfully on rises and decays smoothly on silence.

- **Perceptual `SpeechLevelMapper`**. The raw RMS level from the audio engine is now mapped through a perceptual dB → visual curve before reaching the overlay. Quiet speech registers visibly, loud speech doesn't clip the bars, and the silence floor sits where the user expects it.

### Refactor

- **`PasteCapabilityNotifier` extracted from the indicator widget**. The Auto-Paste capability state (the `ready` / `permissionMissing` / `unsupported` machine shipped in 1.2.19) now lives in a dedicated Riverpod notifier instead of being tangled into the Settings indicator widget. The new onboarding `AutoPasteStep` and the existing Settings indicator both observe the same source of truth, so a permission grant in onboarding immediately reflects in Settings and vice versa.

- **History UI adopts split-view + search-filter-bar naming**. The history pane's internal widgets and providers have been renamed to match the `internal-notes` glossary (`SplitView`, `SearchFilterBar`). No behaviour change — pure terminology alignment so future references match the canonical vocabulary.

- **Shared `LanguageSelector` widget**. Onboarding and Settings now both consume the same dropdown widget for transcription-language selection, eliminating the duplicated pill-row in onboarding and the bespoke dropdown in Settings.

- **`AudioService` routes level through `SpeechLevelMapper`**. The internal audio level path no longer exposes raw RMS to consumers. The new `setWaveformBars` channel is the supported way to drive visualisations, and the legacy `setAudioLevel` hook has been removed.

### Bug Fixes

- **Sentry no longer ingests user-config noise**. Settings-page navigation, preference toggles, and the routine config-load breadcrumbs that contributed nothing diagnostic but inflated event payloads have been filtered out at the breadcrumb level. Crash reports stay focused on the path that led to the failure instead of being buried under setting reads.

- **Disposal guard on `AutoPasteStep`**. The onboarding step now cancels its TCC poll and Sentry breadcrumb timer when disposed, so navigating away mid-grant no longer leaks a timer or fires a breadcrumb against a dead context.

## 1.2.20

### Bug Fixes

- **Release pipeline no longer fails when an action's Post-step exits non-zero**. In v1.2.19 every functional Windows build step (compile, Sentry symbol upload, NSIS installer, MSIX, both artifact uploads) succeeded, but the `subosito/flutter-action` Post-step (cache save on a cache hit) returned a non-zero exit code. That flipped `needs.build-windows.result` to `failure` and the conditional gates on `create-release` and `submit-ms-store` (`result == 'success'`) skipped both jobs, leaving the binaries stranded in the artifact storage with no GitHub Release and no Microsoft Store submission. The workflow now exposes an explicit `build-succeeded` output set by a `Mark build succeeded` step that runs after every real build/upload step. Downstream jobs gate on that output (combined with `!cancelled()`) instead of the job result, so cache-save quirks or other Post-step failures can no longer block a release.

## 1.2.19

### Bug Fixes

- **Auto-Paste now works on ad-hoc-signed macOS builds**. The old code aborted with `Paste failed` whenever `AXIsProcessTrusted()` returned `false`, but on macOS Sequoia that API lies for ad-hoc-signed apps: every rebuild produces a new content hash, TCC binds permissions to that hash, and the visible "Accessibility ON" toggle in System Settings keeps referring to a previous build. The Swift host no longer treats the AX check as a hard gate. Instead it posts the keystroke through **two independent permission channels** (`CGEvent` + AppleScript via `System Events.keystroke`), reports honest success only when at least one channel can be proven to have landed, and includes a structured detail string (`ax=… cg=… as=… target=…`) in the result so silent-drop scenarios are diagnosable from `whispaste.log`.

- **Paste failures are no longer silent when the main window is hidden**. The previous in-app toast was invisible in the normal use case where the user is focused on Terminal / VS Code / Warp and WhisPaste lives in the tray. Three additional surfaces fire on every paste failure: a **native OS notification** via `local_notifier` (Toast on Windows, Notification Center on macOS), a **Dock-icon bounce** (`NSApp.requestUserAttention(.criticalRequest)`) on macOS / **taskbar flash** (`FlashWindowEx(FLASHW_TRAY|FLASHW_TIMERNOFG)`) on Windows, and a **persistent tray-menu badge** ("⚠ Auto-Einfügen blockiert — Berechtigung erteilen") that survives until the next successful paste auto-clears it. Attention requests are throttled to one per minute per failure kind to avoid spamming during a recording session.

### Features

- **Auto-Paste capability indicator in Settings**. The "After Transcription" section now hosts a live status card that probes both permission channels without actually pasting, shown as soon as the user enables `paste` or `clipboardAndPaste` mode. The card surfaces three actionable states (`ready` / `permissionMissing` / `unsupported`) with platform-specific repair actions: **"Test now"** runs a fresh `AXIsProcessTrusted` + AppleScript probe; **"Grant permission"** triggers `AXIsProcessTrustedWithOptions(prompt: true)` and opens System Settings → Privacy → Accessibility; and a new **"Repair permissions"** button that spawns `tccutil reset Accessibility com.whispaste.whispaste && tccutil reset AppleEvents com.whispaste.whispaste`, the documented Apple workaround for stale TCC entries on ad-hoc-signed apps. The repair button is hidden on Windows where TCC doesn't apply.

- **Structured paste-outcome reporting end-to-end**. The native bridges now return `{status, detail}` maps (`success` / `no_target` / `no_accessibility` / `post_failed` on macOS; `success` / `no_target` / `foreground_blocked` / `send_input_failed` on Windows) which Dart maps to a typed `PasteOutcome` enum (`success` / `blocked` / `platformUnavailable` / `noTarget` / `permissionMissing` / `failed`). Toast messages, native notifications, and tray badges are tailored to the specific failure mode so the user gets actionable guidance instead of a generic "Paste failed".

- **Visible native logging via `os_log`** in the macOS Swift host (`subsystem=com.whispaste.paste`) replaces the prior `NSLog` calls, which Apple's unified logging filters from non-Apple processes. Combined with the Dart-side `DesktopPaster.info` line logging the full native detail string, every paste attempt now leaves a triage-ready record in `~/Library/Application Support/WhisPaste/logs/whispaste.log`.

## 1.2.17

### Features

- **Streamlined model selection**: The STT model catalog now exposes exactly one model per quality tier — `whisper-small` (Compact), `whisper-medium` (Balanced), and `whisper-large-v3-turbo` (Premium). The previous catalog mixed redundant variants (`whisper-tiny`, `whisper-base`, non-turbo `whisper-large-v3`) that made tier-based defaults ambiguous and shipped large files for marginal quality wins. Existing installations are migrated automatically on settings load: any removed model ID is rewritten to its tier representative, so users keep a valid selection without manual intervention.

### Cleanup

- **CI/release pipeline consolidation**: The release workflow now triggers only on tag push (a stray merge to `main` no longer burns ~15 min on Win + macOS + MSIX builds whose artifacts are never published). The Windows and MSIX builds were merged into a single job that reuses one `flutter build windows --release` for both the NSIS installer and the MSIX store package, cutting roughly a duplicate Windows build off every release. Redundant `flutter analyze` + `flutter test` steps were dropped from the release job because CI on `dev` already gates them. The flaky Linux secure-storage job was removed (Linux is not a release target and the same path is covered on Win + macOS), the secret scan was deduplicated into a single Ubuntu job, and the changelog-refresh cron dropped from daily to weekly.

## 1.2.16

### Bug Fixes

- **Sentry consent gating**: Transactions are now suppressed alongside events when the user revokes monitoring consent. Previously the kill switch only stopped event capture, so performance spans and Drift query traces could still leak after opt-out. The consent check now runs in the transaction sampler, so revoking consent silences the SDK end-to-end with no restart needed.

### Observability

- **Sentry SDK 9.20 upgrade**: `sentry_flutter` moves from 8.14 to 9.20, with the matching `sentry_dio` and `sentry_drift` integrations enabled. HTTP requests through the update service's Dio client and every Drift database query now produce performance spans, so a slow update check or a regressed query shows up in the Sentry transaction list instead of staying invisible. Trace propagation is explicitly scoped to an empty allow-list so no `sentry-trace` headers leak to third-party APIs.

- **Native crash symbolication**: Release builds upload PDB/DLL symbols on Windows and `.dSYM` bundles on macOS to Sentry via `sentry_dart_plugin` during the release workflow. Native crash frames in the Rust audio engine, the whisper.cpp bridge, and platform plugins now resolve to source lines instead of raw addresses. Symbol upload uses a separate Sentry billing bucket and does not consume the event/span quota.

- **Route breadcrumbs**: A `SentryNavigatorObserver` is wired into both top-level `MaterialApp`s so dialog opens, settings panels, and the review prompt land as navigation breadcrumbs on the next error event — the path that led to a crash is now reconstructable.

### Distribution

- **Microsoft Store submission automated**: The release workflow now pushes a successful MSIX build to the Microsoft Store via the Partner Center Submission API. The "What's new" field is populated from the same AI-enhanced release notes that the GitHub Release uses, in both English and German. The job self-skips when the `MS_STORE_APP_ID` secret is unset, so forks and dispatch-only runs stay clean. Listing copy (description, features) lives in `store/` per locale.

### Cleanup

- **Dependency wave**: `flutter_secure_storage` 9 → 10 (consolidated iOS+macOS pod, Linux drops the `libjsoncpp1` system dep), `drift` family + `analyzer` + `sqlite3` upgraded, Dart utilities (`flutter_soloud`, `flutter_svg`, `lucide_icons_flutter`, `in_app_review`, `mocktail`) on current minor, website npm dependencies refreshed (Tailwind held at 4.2 until an upstream Vite/rolldown compatibility issue is resolved), CI action major pins bumped (checkout v6, setup-node v6, upload-artifact v7, download-artifact v8, withastro/action v6, deploy-pages v5, softprops/action-gh-release v3).

## 1.2.15

### Bug Fixes

- **Auto-Paste reports the real outcome (macOS)**: The macOS paste host now waits for the synthesised ⌘V to complete before reporting success back to Flutter, hard-stops with a clear error when the Accessibility permission is missing, clears stale target-app state when WhisPaste itself is frontmost, and uses the modern `activate(options:)` API on macOS 14+. The Auto-Paste toast no longer claims success when nothing was actually pasted.

### New Features

- **Multi-format export activation**: The history detail panel can now export the selected entry to TXT, MD, CSV, JSON, and DOCX. The action is wired up from the detail panel overflow menu and uses the platform file save dialog — no third-party services involved.

### Removals

- **`Projects` table and `project_id` column removed**: The unused `Projects` table and the `HistoryEntries.project_id` column have been deleted. A one-time destructive Drift v9 → v10 migration drops both on first launch. **Migration note**: Existing user databases auto-migrate from schema v9 to v10 on first launch. The migration is idempotent and requires no user action; transcripts, notes, tags, and timestamps are preserved.

- **Command Palette removed**: The entry-scoped Ctrl+K popup has been removed. All actions it exposed (export, copy, delete, etc.) remain available through the history detail panel's overflow menu, so no functionality is lost.

- **`useVAD` and `vadSensitivity` settings removed**: The Recording stack never read these two settings, so the corresponding UI controls and persisted columns have been dropped. Old persisted `use_vad` / `vad_sensitivity` keys in existing databases are silently ignored — no migration required.

### Cleanup

- **README and website Features alignment**: The README and the website Features section have been trimmed to match the actually-shipping feature set after the removals above. Outdated mentions of Projects, the Command Palette, and the VAD toggle have been removed from public-facing documentation.

## 1.2.13

### Bug Fixes

- **Model-failure classification with re-download prompt**: WhisPaste now classifies whisper-server exit codes more precisely. A code-3 failure (failed to load model) triggers an actionable "Please re-download the model" prompt and clears the cached model path, so a single corrupt or incompatible file no longer locks the user into an unrecoverable state. Subsequent recordings resume normally after re-download.

- **Heartbeat startup timeout**: The STT server heartbeat now enforces a hard deadline during startup. If the server does not become ready within the configured timeout, the pipeline fails fast with a clear error instead of hanging indefinitely while the process idles in the background.

- **Recording idempotency**: Rapid hotkey presses and overlapping trigger signals no longer start a second recording while one is already in flight. The orchestrator gates on the current `RecordingPhase` so only one session is active at a time, preventing corrupted WAV files and duplicate history entries.

- **Hotkey `TypeError` fallback**: On platforms where the hotkey manager returns a non-string key token, WhisPaste now catches the `TypeError` and degrades gracefully instead of crashing. The hotkey is marked as unregistered and the user sees an actionable settings nudge.

### Observability

- **Sentry fingerprint extension**: Error events are now grouped by a richer fingerprint that includes the recording phase and STT status at the time of failure. This collapses noisy duplicate issues in the Sentry dashboard and makes regression tracking more reliable.

- **Info-level guard fires**: Sentry now captures info-level breadcrumbs when safety guards (OOM guard, CPU fallback gate, idempotency gate) activate. These breadcrumbs are attached to the next error event, giving support the full decision trail without PII.

### Removals

- **Smart-Mode dead code removed**: All `SmartMode`-prefixed fields, providers, and UI fragments have been deleted. The feature was never shipped publicly; removing the dead code reduces bundle size and eliminates confusion in the settings diff. No user-visible behaviour changes.

- **Groq STT removed**: The Groq cloud STT backend has been removed from WhisPaste. **Migration note**: Existing users who had Groq selected as their STT provider will automatically fall back to On-Device STT (whisper.cpp) on first launch after the update. No data is lost; the API key stored in secure storage is left intact but is no longer read.

### New Features

- **Deepgram STT — production-ready**: The Deepgram Nova-2 cloud STT backend is now fully functional and supported as a first-class provider alongside OpenAI and On-Device. Real-time streaming transcription, automatic language detection, and speaker diarisation are all supported. Configure your Deepgram API key in Settings → Cloud STT.

- **Free-tier onboarding hints**: Settings now shows inline signup links for Deepgram (free tier: 45 hours/month) and OpenAI (pay-as-you-go) directly beneath the API key fields. New users no longer need to leave the app to find sign-up links.

### Cleanup

- **README and website consistency**: Removed Post-Processing, LLM auto-tagging, and Groq from the README feature list and the website landing page. The public-facing documentation now accurately reflects the shipped feature set.

### Internal Refactors

- **`AppSettings` section-based architecture**: `AppSettings` is now split into focused section classes (`RecordingSettings`, `SttSettings`, `UiSettings`, etc.) instead of a flat record. Each section owns its own `fromDb`/`toDb` logic, making future column additions additive rather than requiring edits across the entire settings surface.

- **STT subsystem modularisation**: The monolithic `SttService` has been split into deep, independently testable modules — `SttProcessManager`, `SttHealthMonitor`, `SttTranscriber`, and `SttProviderRouter`. Each module has its own unit tests and a clearly defined interface boundary.

- **Recording orchestrator decomposition**: `RecordingOrchestrator` has been refactored into three collaborating components — `SafetyGuard` (pre-flight checks and idempotency), `OomRecoveryHandler` (RAM monitoring and retry logic), and `RecordingStateMachine` (phase transitions and event emission). This separation makes the flow easier to test and audit.

- **Floating UI platform host**: The floating button, floating overlay, and recording pill now share a single `FloatingPlatformHost` that manages the native window lifecycle. Duplicated window-positioning and always-on-top logic has been consolidated into one place.

## 1.2.10

### New Features

- **Minimum system requirements enforced**: WhisPaste now checks available RAM at startup and shows a clear, localized error screen when the system does not meet the 8 GB minimum. Users on underpowered hardware receive a friendly explanation with a link to the FAQ instead of encountering confusing failures mid-session.

### Improvements

- **System requirements updated on website**: The FAQ now lists accurate hardware requirements — 8 GB RAM minimum (enforced), 16 GB recommended, and a detailed GPU VRAM table for each model tier (compact ~300 MB, balanced ~900 MB, premium ~2.6 GB). Apple Silicon unified-memory users are also noted.

## 1.2.9

### Bug Fixes

- **Model load failure loop prevented**: When whisper-server exits with code 3 (failed to load model — typically a corrupted or incompatible model file), WhisPaste now fails fast on all subsequent recording attempts with an actionable "Please re-download" message instead of silently retrying indefinitely. The failed-model flag resets when the user re-downloads the model or changes model/GPU settings.

- **Duplicate error toast eliminated**: The generic "Something went wrong" toast no longer appears alongside the specific "model file corrupted" error message after a code-3 model load failure. The exit handler's specific message now takes priority.

- **Misleading "Could not save audio file" toast fixed**: When a recording pipeline abort is caused by STT startup failure (not by an audio capture issue), WhisPaste now shows the STT error message instead of the confusing "Could not save the audio file" toast.

## 1.2.8

### Bug Fixes

- **GPU → CPU automatic fallback**: When the speech engine crashes with a fatal GPU error (e.g. on older NVIDIA cards like GTX 650 with insufficient VRAM or unsupported compute features), WhisPaste now silently activates CPU mode instead of showing an error dialog. Subsequent recordings automatically use the CPU backend. The fallback resets when the user changes the GPU setting or active model.

- **Flash-attention compatibility**: GTX 650 and other pre-Turing GPUs (pre-sm_75) no longer receive the `--flash-attn` flag, preventing the STATUS_STACK_BUFFER_OVERRUN crash that occurred on these cards at runtime.

- **Waveform animation**: The audio visualiser in the macOS recording overlay is no longer static at high amplitude levels. The per-frame dual-oscillator now applies correct normalisation so the waveform remains visibly dynamic across the full input range.

### New Features

- **Review prompts**: After a configurable number of successful recordings, the app now gently invites users to rate WhisPaste in the App Store / Microsoft Store or star the project on GitHub. The prompt is non-intrusive and only shown once per milestone.

- **Download support modal**: The landing page now shows a friendly post-download modal with low-pressure information about how visitors can support the project (review, star, share).

### Infrastructure

- Supabase security advisor warnings resolved: RLS policies tightened, analytics functions hardened against injection, unused indexes dropped.

## 1.2.7

### Bug Fixes

- **Crash on quit**: Fixed a SIGABRT crash when quitting via the floating button context menu or tray icon. The Drift/SQLite database is now explicitly closed before the window is destroyed, preventing an assertion failure in SQLite's mutex cleanup.

### Screenshots & Store Assets

- Mac App Store screenshots now use the correct **1440×900** resolution (16:10) with authentic macOS window chrome (traffic-light close/minimise/maximise dots). Previously, both stores incorrectly used 1920×1080 Windows-style chrome.
- OG images no longer carry a double window frame — the fake CSS title bar overlay has been removed and border-radius corrected to match real macOS window corners.
- Screenshot pipeline is now fully cross-platform (macOS + Windows): golden tests generate separate `windowsStoreScreenshots/` and `macStoreScreenshots/` sets; the Node compositor renders each store panorama at its native resolution with injected CSS variables.

## 1.2.6

### Improvements

- MSIX package for Microsoft Store now included in release artifacts with correct Partner Center publisher identity.
- MSIX build failure now properly blocks the release workflow instead of being silently ignored.

## 1.2.3

### Bug Fixes

- **History detail editor**: Enter, Backspace, and Delete keys are no longer intercepted by list-level keyboard shortcuts when a text field has focus. All standard editing operations (line breaks, character deletion, cursor movement) now work correctly in the transcript editor, notes field, and tag input.

## 1.2.2

### macOS

- macOS app ships as a native ARM64 DMG with every release — direct download and Gatekeeper instructions included.
- Floating button context menu expanded: open WhisPaste, start recording, view history, open settings, or quit — all accessible via right-click on the floating button.
- macOS menu bar icon now displays correctly and resolves paths reliably across all bundle layouts.

## 1.2.1

Re-release of 1.2.0 with consistent version metadata and release pipeline
stabilization. No user-visible app changes.

## 1.2.0

Complete rewrite: WhisPaste is now a native **Flutter** application replacing the previous Go+WebView2 architecture.

### What's New

- **Native Flutter UI** — truly cross-platform (Windows, macOS, Linux, iOS, Android) with a single Dart codebase
- **SQLite via Drift** — all data stored locally in a type-safe database; no shared config files
- **Riverpod state management** — reactive, testable, maintainable architecture
- **Unified design system** — WpToast notifications, WpDialog modals, consistent theme tokens
- **Recording pill overlay** — slim, elegant status bar during dictation with progress ring
- **Floating button** — always-on-top recording trigger with context menu and multi-monitor support
- **Premium UI** — warm gradients, frosted glass effects, micro-animations, WCAG AA contrast
- **469+ automated tests** — widget, unit, and integration tests with >90% feature coverage

### Architecture

- All Go backend code removed — zero Go dependencies
- CI/CD updated for Flutter-only builds (Windows debug + release)
- Security scanning migrated from golangci-lint/gosec to flutter analyze + gitleaks
- Version centralized in `pubspec.yaml` with `app_info.dart` constant

### Breaking Changes

- Settings are stored in SQLite, not the legacy Go `config.json`
- No Go FFI bridge — all inference via whisper-server subprocess

---

## 1.1.3.0

A polished UI update that makes WhisPaste feel faster, clearer, and more intuitive to use.

### Highlights

- Redesigned dashboard, Smart Mode, and Voice Snippets screens with cleaner cards and better spacing.
- Smart Mode and Voice Snippets now have separate AI provider settings — choose local or cloud independently.
- Silence removal is now a single, unified setting combining voice detection and trim in one step.
- Page transitions are now smooth and animated for a more premium feel.
- Auto-generated tags now use Title Case and block system tags from leaking into your entries.

### UI and copy improvements

- Settings reorganized into clearer sections with more descriptive labels.
- Replaced jargon like "Transcription" and "Diktat" with everyday language throughout.
- All German translations reviewed and aligned with the current English copy.
- Contextual tips explain features where you need them, not just in onboarding.

### Reliability

- Fixed a race condition when switching pages quickly during transitions.
- Version metadata in Windows resources now stays in sync with the release version.
- Silence detection margins tuned to industry best practices (250 ms pre-speech, 350 ms post-speech).

## 1.1.2.0

This release focuses on safer crash reporting, clearer setup flows, and more consistent communication across the app and website.

### Highlights

- Crash reporting now uses a Supabase relay instead of shipping a direct Discord webhook in the app.
- Release builds now require the public crash-relay URL, so packaged builds keep crash delivery working reliably.
- The onboarding try-dictation flow no longer marks onboarding complete too early while transcription is still finishing.

### Privacy and security

- Public builds ship only the relay URL. Private secrets stay server-side in Supabase.
- Crash-message sanitization is stricter for API keys, bearer tokens, and similar secrets.
- Setup docs now clearly explain which Supabase values are public and which must never be committed.

### Product and copy updates

- Website copy now reflects the real product setup more accurately: local transcription or the cloud provider you choose.
- Privacy messaging now explains optional crash reporting more transparently.
- Download and release messaging no longer implies an OpenAI-only setup.

### Reliability

- Release workflow validation now fails early if the crash-relay configuration is missing or malformed.
- Build metadata stays aligned with the release version more consistently.
