# Network Allowlist

WhisPaste is a local-first desktop dictation app. This page lists every host
the app can contact on its own, what it sends, whether it is on by default and
how to switch it off. Everything else you might click (GitHub, Ko-fi, PayPal,
X, Votepit, …) is a regular link opened in your browser, not a call the app makes
for you.

Several connections are **on by default** (opt-out): anonymous usage
statistics (Matomo), crash reports (Sentry), the update check (GitHub) and the
project numbers (api.whispaste.de). Usage statistics and crash reports never
contain your audio, transcribed text, history, tags or notes; they can be
switched off in Settings → Privacy (or on the Privacy step of the onboarding),
the update check under Settings → Updates, and the project numbers by hiding
the "Get involved" section on the Overview.

## App-initiated connections

On a first start the app makes none of the background connections below before the final onboarding page, where the usage statistics and crash report switches sit. The model download in onboarding is the one exception: pressing the start button on the welcome page is the consent to download the speech model shown there from `huggingface.co`, and the download keeps running in the background while you go through the remaining pages, including the privacy step. If a speech model from the catalog is already on disk, the welcome page preselects it and the start button downloads nothing.

| Host | Purpose | Default | Trigger | Data sent | How to switch off |
| --- | --- | --- | --- | --- | --- |
| Self-hosted Matomo server (URL injected at build time, not hardcoded; operated by the WhisPaste maintainers in the EU) | Anonymous usage statistics | **On** (opt-out) | One event at app start, one "alive" ping per day (on a first run both wait until you have seen the privacy step and made your choice; nothing is sent before), aggregated feature counters (sent in batches when the app goes to the background, on quit, and every 15 minutes as a crash safety net), onboarding steps, optional onboarding answers (job category and how you found WhisPaste, as fixed IDs only), update-check outcome, names of changed settings (never their values) | Event counters plus app version, OS, speech-to-text provider type, install channel, UI language, update channel, a random visitor ID that is new on every app start and never stored, and a weekly rotating pseudonym (hash of a random local value and the calendar week). When statistics are on: the speech model as a catalog name (small, medium, large-v3-turbo, parakeet or cloud), coarse hardware classes (RAM class, GPU vendor class, Mac chip family, compute backend), coarse speed classes, model-download outcomes with an error class, whether the recommended model was kept, and the first-name edit state (kept, edited or cleared; never the name). Cookieless; IP truncated to two bytes (last two bytes zeroed) before storage; location is derived from the full address on arrival; raw data is deleted after 180 days. Never audio, text, history, snippets, tags, notes, API keys, hotkeys, file paths or the target app | Settings → Privacy → "Help make WhisPaste better" |
| `*.ingest.de.sentry.io` (Sentry, EU data region) | Crash and error reports | **On** (opt-out) | When the app crashes, hangs for 5 seconds or more (on a first run, before the privacy choice is made, the crash reporter is not started at all, so nothing is sent; reporting begins with the next start) (native app-hang report), or hits a serious error (error or fatal level only). At most 3 reports per error and 30 per session. No performance traces, no session tracking | Stack trace, app version, OS/architecture, install channel, the last app log lines (up to 30; they never contain transcribed text), and a pseudonymous random per-install ID (12 hex characters, created on first launch and not derived from the machine). IP addresses are not stored, and error data is kept for 30 days. The OS account name in file paths is replaced with `<user>` before sending. Events containing secrets such as API keys are dropped. No screenshots, no view hierarchy, no default PII | Settings → Privacy → "Send crash reports". Switching it off stops Sentry immediately, including crash and app-hang reports; on later launches Sentry is not started at all. Switching it back on takes effect after a restart |
| `api.whispaste.de` (`GET /v1/public/social-stats`) | Live numbers for the "Get involved" section: GitHub stars and YouTube subscribers | **On** (opt-out) | When the Overview shows the "Get involved" section, or the Support page shows the star count in "Help without money", at most once every 24 hours, and only while one of these pages is open. Never at start-up and never on the hotkey path | Nothing beyond the HTTPS request itself and a `WhisPaste` user agent (no version, no identifier, no cookie, no setting, nothing about your dictation) | Hide the section: "Hide this section" on the Overview or "Customise overview" → "Get involved" (then neither the Overview nor the Support page makes a request) |
| `api.met.no` (MET Norway, `locationforecast/2.0/compact`) | Weather forecast for the optional "Weather" card on the Overview | **Off** (opt-in) | Only after you switch the card on under "Customise overview" and choose a place: while the Overview is visible, when the last forecast has expired (`Expires`), at most about once an hour, after a failure at most every 30 minutes, after `429` not before `Retry-After`. A new place asks at once. Never at start-up, never in the background, never on the hotkey path | The chosen place's coordinates rounded to two decimals (about 1 km), `If-Modified-Since` from the last answer, and a `WhisPaste/<version> (+https://whispaste.de; <contact address>)` user agent as MET Norway requires; no identifier, no cookie | Remove the place in the card or hide the card under "Customise overview" → "Weather" |
| `nominatim.openstreetmap.org` (`/search`) | Place search in the "Weather" card's dialog | **Action** | Only when you press "Search" or Enter in the dialog, never while typing, at most one request per second; repeated searches are answered from memory | The search text, the app language (`accept-language`) and the same user agent; no location services, no identifier | Do not search |
| `api.whispaste.de` (`POST /v1/newsletter/subscribe`) | Newsletter sign-up from the "Get involved" section (double opt-in) | Only on request | Only when you tick the consent box and press "Sign up". No retry, nothing at start-up | Your email address, the newsletter language (your UI language), the source `app`, the consent version, the time between showing the form and sending it, an empty spam-trap field, and a `WhisPaste` user agent. The app does not store the address. The server sends a confirmation link; nothing else is sent until you confirm | Don't sign up; unsubscribe through the link in every newsletter email |
| `api.github.com` | Update check (Linux, portable/installer fallback) | **On** | Shortly after app start (on a first run: after the privacy step) and every 24 hours while the app runs, and when you press "Check now" | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Settings → Updates → "Check for Updates" |
| `github.com` (`releases/latest/download/appcast.xml`) | Signed update feed (macOS DMG, Windows installer) | **On** | At app start (on a first run: after the privacy step) and every 24 hours while the app runs, and on manual "Check for updates" | Same as above | Settings → Updates → "Check for Updates" |
| `huggingface.co` (and its download CDN) | Downloads on-device model weights (whisper.cpp GGML, Parakeet ONNX, and the optional Smart Mode Gemma model) | Only on request | When you download a model in onboarding or Settings; a corrupt Whisper model file is re-downloaded automatically | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Don't download models (on-device transcription needs one) |
| `github.com` (`releases/download/cuda-<pack id>/…`) | Downloads the optional CUDA acceleration pack (Windows/Linux, NVIDIA) | Only on request | When you request the pack in Settings | Nothing beyond the HTTPS request itself and a `WhisPaste/<version>` user agent | Don't download the pack (on-device transcription works without it) |
| `api.openai.com` (`/v1/audio/transcriptions`) | Cloud speech-to-text (OpenAI speech-to-text API, model `gpt-transcribe`) | Off | Each recording, only if you choose OpenAI as your speech-to-text provider and add your own API key (BYOK) | Recorded audio, language, your custom vocabulary, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.deepgram.com` | Cloud speech-to-text (Deepgram Nova-3) | Off | Each recording, only if you choose Deepgram and add your own API key (BYOK) | Recorded audio, language, your API key | Settings → Speech Recognition → Service "Locally on Device" |
| `api.openai.com` (`/v1/chat/completions`) | Smart Mode text cleanup in the cloud | Off | Each recording with an active Smart Mode preset, only if you switch the Smart Mode service to OpenAI (uses the same OpenAI API key) | The transcribed text and the preset's instructions, your API key | Settings → Smart Mode → Service "Locally on Device", or leave Smart Mode off |
| Your own OpenAI-compatible endpoint (the address you enter, e.g. LM Studio, Ollama, llama.cpp on this device or your network, or a third-party provider) | Speech-to-text and Smart Mode through a server you run or choose | Off | Each recording or Smart Mode run, only if you choose "Custom endpoint" (speech) or the custom service (Smart Mode). "Test connection" sends one `GET /models` request without audio or text | Audio (speech) or the transcribed text (Smart Mode), the model name, your optional key. Addresses on this device or in your local network (localhost, 127.0.0.1, ::1, `.local` names) stay local; a private network address (10/8, 172.16/12, 192.168/16, 169.254/16, fc00::/7, fe80::/10, `.local`) stays in your local network; any other address receives the data. Plain http is accepted only on this device and in the local network (with a warning); servers on the internet need https | Settings → Speech Recognition → Service "Custom endpoint", or Settings → Smart Mode → Service, or leave both off |
| The RSS or Atom feeds you choose for the Overview's "News" block (the WhisPaste blog `whispaste.de/blog/feed.xml` is suggested) | Titles, sources and dates of the newest feed entries | Off | Only while the Overview shows the "News" block and the window is active: once for each feed you add, then at most once an hour per feed. Nothing at app start, nothing in the background, nothing without a feed | A plain HTTPS (or http, if you enter it) `GET` of the feed address with the user agent `WhisPaste`; no identifier, no cookie. Answers above 2 MiB or 10 s are dropped | Customize overview → "News" off, or remove the feeds under "Sources" |
| `api.whispaste.de` (`POST /v1/feedback`, `POST /v1/feedback/withdraw`; netcup, Germany, MySQL) | Feedback form submission and withdrawal of a quote approval | Only on request | Only when you submit the in-app feedback form | Rating, category, your feedback text, app version, UI language, a hashed device identifier; contact e-mail and reply language only if you fill them in | Don't submit the form |

Store and package-manager builds (Mac App Store, Microsoft Store, Homebrew,
Scoop) never check for updates themselves — the store or package manager does
that — so the two update-check GitHub rows above and the CUDA pack row don't apply to them.

The optional local automation API is a server, not an outgoing connection: it
is off by default, binds to the loopback interface only (`127.0.0.1`/`::1`)
and requires a bearer token.

## Windows certificate checks triggered by HTTPS

The Windows installer/portable update check uses WinSparkle and Windows
WinINet. While validating the HTTPS certificate, Windows CryptoAPI can fetch
certificate revocation lists (CRLs) over **HTTP, port 80**, inside the calling
process. A connection attributed to WhisPaste can therefore be a Windows
certificate check triggered by its HTTPS update request.

Observed on 2026-11-11: `yr1.c.lencr.org`, specifically
`http://yr1.c.lencr.org/57.crl`, served through Cloudflare. Windows fetched this
Let's Encrypt CRL while checking the certificate of
`release-assets.githubusercontent.com`, the update-feed redirect destination.
The request was `GET /57.crl` with `Microsoft-CryptoAPI/10.0` as its user agent;
it contained no dictation, telemetry or app credentials. The server sees the
source IP and requested CRL. The CRL is signed by its issuer; the update feed
itself still travels over HTTPS. See [Let's Encrypt's explanation of
lencr.org](https://letsencrypt.org/docs/lencr.org/).

The certificate chain and Windows cache determine which certificate-service
hosts are contacted and when; this hostname is an observed example, not a
permanent IP/host allowlist. Turning off update checks prevents this update
trigger, but does not disable certificate checks for other apps or other HTTPS
requests. WhisPaste does not disable Windows certificate validation.

## Not app-initiated (opened in your default browser instead)

`github.com`, `github.com/sponsors/...`, `ko-fi.com`, `buymeacoffee.com`, `www.paypal.com/donate/...`, `x.com`, `app.votepit.com`,
and the WhisPaste website (`whispaste.de`) are only ever opened as external
links from About/Settings/feedback screens — the app never contacts them in
the background.

## Notes

- On-device transcription (the default) needs no network connection once the
  model is downloaded — audio never leaves your machine. With crash reports,
  usage statistics and update checks switched off, the app still asks
  api.whispaste.de for the project numbers while the Overview or the Support
  page is open; hiding the "Get involved" section stops that request on both pages. Apart from that it
  connects only where you trigger a download, a cloud provider, a form or
  the feeds you chose for the "News" block (off by default).
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
- Proxy and offline use: Dart requests use the default `HttpClient`, so only
  the `https_proxy`, `http_proxy` and `no_proxy` environment variables are
  honoured. These requests do not evaluate the operating system proxy or PAC
  files; the native Windows updater uses WinINet's system configuration. The
  local automation client connects directly, as it only talks to loopback.
  Without a network, local transcription works fully; speech models can be
  downloaded on another computer and copied over manually (see the manual,
  section on offline model download).
- Crash reports, usage statistics and update checks can each be switched off
  independently; the feedback form is only used when you submit it.
- Clipboard content never leaves your machine. The app reads it only to paste
  a dictation and put back what was on the clipboard before, and for the
  clipboard history, which is held in memory only. It is not stored on disk
  and not part of any connection listed above. WhisPaste does not write
  dictation or clipboard content to the log. Where an error message could
  contain such content, only the error type is logged; every log line is
  also stripped of paths and secrets.

See [`SECURITY.md`](./SECURITY.md) for how app requests are secured
(HTTPS-only, no plaintext fallbacks) and how to report a vulnerability.
Windows certificate-service HTTP requests are described separately above.
