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
| Self-hosted Matomo server (URL injected at build time, not hardcoded; operated by the WhisPaste maintainers in the EU) | Anonymous usage statistics | **On** (opt-out) | One event at app start, one "alive" ping per day, aggregated feature counters (sent in batches when the app goes to the background, on quit, and every 15 minutes as a crash safety net), onboarding steps, optional onboarding answers (job category and how you found WhisPaste, as fixed IDs only), update-check outcome, names of changed settings (never their values) | Event counters plus app version, OS, speech-to-text provider type, install channel, UI language, update channel, a random visitor ID that is new on every app start and never stored, and a weekly rotating pseudonym (hash of a random local value and the calendar week). When statistics are on: the speech model as a catalog name (small, medium, large-v3-turbo, parakeet or cloud), coarse hardware classes (RAM class, GPU vendor class, Mac chip family, compute backend), coarse speed classes, model-download outcomes with an error class, whether the recommended model was kept, and the first-name edit state (kept, edited or cleared; never the name). Cookieless; IP truncated to two bytes (last two bytes zeroed) before storage; location is derived from the full address on arrival; raw data is deleted after 180 days. Never audio, text, history, snippets, tags, notes, API keys, hotkeys, file paths or the target app | Settings → Privacy → "Help make WhisPaste better" |
| `*.ingest.de.sentry.io` (Sentry, EU data region) | Crash and error reports | **On** (opt-out) | When the app crashes, hangs for 5 seconds or more (native app-hang report), or hits a serious error (error or fatal level only). At most 3 reports per error and 30 per session. No performance traces, no session tracking | Stack trace, app version, OS/architecture, install channel, the last app log lines (up to 30; they never contain transcribed text), and a pseudonymous random per-install ID (12 hex characters, created on first launch and not derived from the machine). IP addresses are not stored, and error data is kept for 30 days. The OS account name in file paths is replaced with `<user>` before sending. Events containing secrets such as API keys are dropped. No screenshots, no view hierarchy, no default PII | Settings → Privacy → "Send crash reports". Switching it off stops Sentry immediately, including crash and app-hang reports; on later launches Sentry is not started at all. Switching it back on takes effect after a restart |
| `api.whispaste.de` (`GET /v1/public/social-stats`) | Live numbers for the "Get involved" section: GitHub stars and YouTube subscribers | **On** (opt-out) | When the Overview shows the "Get involved" section, at most once every 24 hours, and only while the Overview is open. Never at start-up and never on the hotkey path | Nothing beyond the HTTPS request itself and a `WhisPaste` user agent (no version, no identifier, no cookie, no setting, nothing about your dictation) | Hide the section: "Hide this section" on the Overview or "Customise overview" → "Get involved" (then no request is made) |
| `api.github.com` | Update check (Linux, portable/installer fallback) | **On** | Shortly after app start and every 24 hours while the app runs, and when you press "Check now" | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Settings → Updates → "Check for Updates" |
| `github.com` (`releases/latest/download/appcast.xml`) | Signed update feed, stable channel (macOS DMG, Windows installer) | **On** | At app start and every 24 hours while the app runs, and on manual "Check for updates" | Same as above | Settings → Updates → "Check for Updates" |
| `raw.githubusercontent.com` | Signed update feed, beta channel | Off | Same as above, only if you opted into the beta channel | Same as above | Settings → Updates → "Beta Updates" |
| `huggingface.co` (and its download CDN) | Downloads on-device model weights (whisper.cpp GGML, Parakeet ONNX, and the optional Smart Mode Gemma model) | Only on request | When you download a model in onboarding or Settings; a corrupt Whisper model file is re-downloaded automatically | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Don't download models (on-device transcription needs one) |
| `api.openai.com` (`/v1/audio/transcriptions`) | Cloud speech-to-text (OpenAI speech-to-text API, model `gpt-transcribe`) | Off | Each recording, only if you choose OpenAI as your speech-to-text provider and add your own API key (BYOK) | Recorded audio, language, your custom vocabulary, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.deepgram.com` | Cloud speech-to-text (Deepgram Nova-3) | Off | Each recording, only if you choose Deepgram and add your own API key (BYOK) | Recorded audio, language, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.openai.com` (`/v1/chat/completions`) | Smart Mode text cleanup in the cloud | Off | Each recording with an active Smart Mode preset, only if you switch the Smart Mode service to OpenAI (uses the same OpenAI API key) | The transcribed text and the preset's instructions, your API key | Settings → Smart Mode → Service "Locally on Device", or leave Smart Mode off |
| Your own OpenAI-compatible endpoint (the address you enter, e.g. LM Studio, Ollama, llama.cpp on this device or your network, or a third-party provider) | Speech-to-text and Smart Mode through a server you run or choose | Off | Each recording or Smart Mode run, only if you choose "Custom endpoint" (speech) or the custom service (Smart Mode). "Test connection" sends one `GET /models` request without audio or text | Audio (speech) or the transcribed text (Smart Mode), the model name, your optional key. Addresses on this device or in your local network (localhost, 127.0.0.1, ::1, `.local` names) stay local; a private network address (10/8, 172.16/12, 192.168/16, 169.254/16, fc00::/7, fe80::/10, `.local`) stays in your local network; any other address receives the data. Plain http is accepted only on this device and in the local network (with a warning); servers on the internet need https | Settings → Speech Recognition → Service "Custom endpoint", or Settings → Smart Mode → Service, or leave both off |
| Supabase project host (URL injected at build time, not hardcoded) | Feedback form submission | Only on request | Only when you submit the in-app feedback form | Rating, category, your feedback text, app version, UI language, a hashed device identifier; contact e-mail and reply language only if you fill them in | Don't submit the form |

Store and package-manager builds (Mac App Store, Microsoft Store, Homebrew,
Scoop) never check for updates themselves — the store or package manager does
that — so the three GitHub rows above don't apply to them.

The optional local automation API is a server, not an outgoing connection: it
is off by default, binds to the loopback interface only (`127.0.0.1`/`::1`)
and requires a bearer token.

## Not app-initiated (opened in your default browser instead)

`github.com`, `github.com/sponsors/...`, `ko-fi.com`, `buymeacoffee.com`, `x.com`, `app.votepit.com`,
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
- Your own OpenAI-compatible endpoint is also opt-in and bring-your-own-key.
  Its address is yours to choose: a server on this device or in your local
  network keeps the data there, any other server receives it. Plain http is
  refused for servers on the internet, so the key and the data are not sent
  unencrypted over it; on the local network it is allowed with a warning.
  The address must not carry credentials; the key goes into the secure
  credential store.
- Crash reports, usage statistics and update checks can each be switched off
  independently; the feedback form is only used when you submit it.
- Clipboard content never leaves your machine. The app reads it only to paste
  a dictation and put back what was on the clipboard before, and for the
  clipboard history, which is held in memory only. It is not stored on disk
  and not part of any connection listed above. WhisPaste does not write
  dictation or clipboard content to the log. Where an error message could
  contain such content, only the error type is logged; every log line is
  also stripped of paths and secrets.

See [`SECURITY.md`](./SECURITY.md) for how these connections are secured
(HTTPS-only, no plaintext fallbacks) and how to report a vulnerability.
