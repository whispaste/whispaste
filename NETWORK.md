# Network Allowlist

WhisPaste is a local-first desktop dictation app. This page lists every host
the app can contact on its own, what it sends, whether it is on by default and
how to switch it off. Everything else you might click (GitHub, Ko-fi, X,
Votepit, …) is a regular link opened in your browser, not a call the app makes
for you.

Two of these connections are **on by default** (opt-out): anonymous usage
statistics (Matomo) and crash reports (Sentry). Both never contain your audio,
transcribed text, history, tags or notes, and both can be switched off in
Settings → Privacy (or on the Privacy step of the onboarding).

## App-initiated connections

| Host | Purpose | Default | Trigger | Data sent | How to switch off |
| --- | --- | --- | --- | --- | --- |
| Self-hosted Matomo server (URL injected at build time, not hardcoded; operated by the WhisPaste maintainers in the EU) | Anonymous usage statistics | **On** (opt-out) | One event at app start, one "alive" ping per day, aggregated feature counters (sent in batches every 15 minutes and on quit), onboarding steps, update-check outcome, names of changed settings (never their values) | Event counters plus app version, OS, speech-to-text provider type, install channel, UI language, update channel and a weekly rotating pseudonym (hash of a random local value and the calendar week). Cookieless; IP anonymised on the server. Never audio, text, history, snippets, tags, notes, API keys, hotkeys, file paths or the target app | Settings → Privacy → "Share anonymous usage statistics". Also skipped when the `DNT=1` environment variable is set |
| `*.ingest.de.sentry.io` (Sentry, EU data region) | Crash and error reports | **On** (opt-out) | When the app hits an error or crash | Stack trace, app version, OS/architecture, install channel, the last 30 app log lines (which never contain transcribed text) and a device hash (truncated MD5 of the host name). Events containing secrets such as API keys are dropped. No screenshots, no view hierarchy, no default PII | Settings → Privacy → "Error Reporting" |
| `*.ingest.de.sentry.io` (Sentry, EU data region) | Performance traces | **On** together with crash reports | A small sample of app operations (0.5 % in release builds, capped at 20 per hour) | Timings of app start, dialogs, database queries (SQL statement templates only, never the bound values) and model/update downloads (GitHub and Hugging Face URLs). Log lines are stripped from traces | Same switch as crash reports (Settings → Privacy → "Error Reporting") |
| `api.github.com` | Update check (Linux, portable/installer fallback) | **On** | Shortly after app start, and when you press "Check now" | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Settings → Updates → "Check for Updates" |
| `github.com` (`releases/latest/download/appcast.xml`) | Signed update feed, stable channel (macOS DMG, Windows installer) | **On** | At app start and every 24 hours while the app runs, and on manual "Check for updates" | Same as above | Settings → Updates → "Check for Updates" |
| `raw.githubusercontent.com` | Signed update feed, beta channel | Off | Same as above, only if you opted into the beta channel | Same as above | Settings → Updates → "Beta Updates" |
| `huggingface.co` (and its download CDN) | Downloads on-device model weights (whisper.cpp GGML, Parakeet ONNX, and the optional Smart Mode Gemma model) | Only on request | When you download a model in onboarding or Settings; a corrupt Whisper model file is re-downloaded automatically | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Don't download models (on-device transcription needs one) |
| `api.openai.com` (`/v1/audio/transcriptions`) | Cloud speech-to-text (OpenAI Whisper API) | Off | Each recording, only if you choose OpenAI as your speech-to-text provider and add your own API key (BYOK) | Recorded audio, language, your custom vocabulary, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.deepgram.com` | Cloud speech-to-text (Deepgram Nova-3) | Off | Each recording, only if you choose Deepgram and add your own API key (BYOK) | Recorded audio, language, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.openai.com` (`/v1/chat/completions`) | Smart Mode text cleanup in the cloud | Off | Each recording with an active Smart Mode preset, only if you switch the Smart Mode service to OpenAI (uses the same OpenAI API key) | The transcribed text and the preset's instructions, your API key | Settings → Smart Mode → Service "Locally on Device", or leave Smart Mode off |
| Supabase project host (URL injected at build time, not hardcoded) | Feedback form submission | Only on request | Only when you submit the in-app feedback form | Rating, category, your feedback text, app version, UI language, a hashed device identifier; contact e-mail and reply language only if you fill them in | Don't submit the form |

Store and package-manager builds (Mac App Store, Microsoft Store, Homebrew,
Scoop) never check for updates themselves — the store or package manager does
that — so the three GitHub rows above don't apply to them.

The optional local automation API is a server, not an outgoing connection: it
is off by default, binds to the loopback interface only (`127.0.0.1`/`::1`)
and requires a bearer token.

## Not app-initiated (opened in your default browser instead)

`github.com`, `github.com/sponsors/...`, `ko-fi.com`, `x.com`, `app.votepit.com`,
and the WhisPaste website (`whispaste.de`) are only ever opened as external
links from About/Settings/feedback screens — the app never contacts them in
the background.

## Notes

- On-device transcription (the default) needs no network connection once the
  model is downloaded — audio never leaves your machine. With crash reports,
  usage statistics and update checks switched off, the app makes no
  connection of its own at all.
- Cloud speech-to-text (OpenAI/Deepgram) and cloud Smart Mode (OpenAI) are
  opt-in and bring-your-own-key (BYOK): your API key is stored in the
  OS-native secure credential store and only ever sent to that provider's own
  API, directly from your machine.
- Crash reports, usage statistics and update checks can each be switched off
  independently; the feedback form is only used when you submit it.

See [`SECURITY.md`](./SECURITY.md) for how these connections are secured
(HTTPS-only, no plaintext fallbacks) and how to report a vulnerability.
