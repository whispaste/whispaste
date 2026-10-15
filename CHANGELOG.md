# Changelog

All entries are written in English.

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

- **History UI adopts split-view + search-filter-bar naming**. The history pane's internal widgets and providers have been renamed to match the `CONTEXT.md` glossary (`SplitView`, `SearchFilterBar`). No behaviour change — pure terminology alignment so future references match the canonical vocabulary.

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
