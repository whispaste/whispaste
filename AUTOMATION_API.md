# Local Automation API

WhisPaste can expose a small, local-only HTTP API for triggering dictation,
reading the latest history entry, or inserting a saved snippet from your own
scripts — useful for wiring WhisPaste into a shell script, a keyboard-macro
tool, or another app's automation layer.

The API is **off by default**. It binds only to the loopback interface
(`127.0.0.1` / `::1`) — it is never reachable from the network, even on the
same LAN — and every request must carry a bearer token.

## Enabling it

1. Open **Settings → Local Automation API**.
2. Toggle **Enable local automation API**.
3. Copy the **Bearer token** shown once the API is running (the copy button
   next to it copies it to your clipboard). Regenerating the token
   immediately invalidates the previous one — no server restart needed.

By default the API listens on port `8765`. If that port is already taken by
something else on your machine, WhisPaste automatically falls back to the
next port (up to 19 additional ports, i.e. `8765`–`8784`) instead of failing
outright — the Settings page shows which port actually ended up bound. You
can also set a **Custom port** in Settings if you'd rather pin a specific
one; the same automatic fallback still applies if that port is taken.

## Endpoint reference

All endpoints require the header:

```
Authorization: Bearer <TOKEN>
```

A request with a missing or incorrect token gets `401 {"error": "unauthorized"}`
regardless of endpoint.

### `POST /v1/dictation/trigger`

Triggers dictation — the same action as pressing the global hotkey. Dictation
is a **toggle**: with no recording in progress, this call *starts* one and
returns immediately; with a recording already in progress, this call *stops*
it and — because stopping means running the full transcription pipeline — the
HTTP response doesn't come back until transcription (and, if Smart Mode is
active, cleanup) has actually finished. There's no separate "stop" endpoint;
call this same endpoint again to stop whatever you just started.

**Request body** (optional — omit entirely, or send `{}`, for the original
fire-and-forget behaviour):

```json
{ "wait": true, "language": "en" }
```

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `wait` | boolean | `false` | Only affects a call that *stops* a recording (see above): when `true`, the response includes the finished `transcript`. The call already blocks until the pipeline finishes either way — `wait` only controls whether the result is reported back, not how long the request takes. Ignored (has no effect) on a call that *starts* a recording, since there's nothing to report yet. |
| `language` | string | none (use the configured language) | Overrides the configured STT language for **the recording this call starts** — e.g. `"en"`, `"de"`, `"fr"`, or `"auto"` for language auto-detection. Only meaningful on a call that starts a recording; ignored on a call that stops one. Use this to dictate in a different language than your usual setting for a single call, without touching Settings. Any two-letter code WhisPaste's language picker supports is accepted; an unrecognised code is rejected with `400`, not silently ignored. |

**Responses:**

| Status | Body | Meaning |
| --- | --- | --- |
| 200 | `{"status": "triggered", "recording": true}` | This call **started** a new recording. `wait`/`language` from the request, if any, were applied. |
| 200 | `{"status": "triggered", "recording": false}` | This call **stopped** an in-progress recording; the pipeline has finished. Sent when `wait` was `false`/omitted. |
| 200 | `{"status": "triggered", "recording": false, "transcript": "..."}` | Same as above, but with `wait: true` — `transcript` holds the finished text (an empty string is possible, e.g. silence). |
| 400 | `{"error": "invalid_request"}` | The body isn't valid JSON, `wait` isn't a boolean, or `language` isn't a recognised code |
| 401 | `{"error": "unauthorized"}` | Missing/invalid bearer token |
| 500 | `{"error": "trigger_failed"}` | Triggering dictation threw an exception |

```bash
# Fire-and-forget, exactly like pressing the hotkey twice (start, then stop):
curl -X POST http://127.0.0.1:8765/v1/dictation/trigger \
  -H "Authorization: Bearer <TOKEN>"

# Start a recording, forcing French recognition for this one dictation:
curl -X POST http://127.0.0.1:8765/v1/dictation/trigger \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"language": "fr"}'

# Stop the recording just started above and get the transcript back directly,
# instead of reading it via GET /v1/history/latest afterwards:
curl -X POST http://127.0.0.1:8765/v1/dictation/trigger \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"wait": true}'
```

### `GET /v1/dictation/status`

Reports whether a recording/transcription is currently in progress — useful
to check *before* calling `POST /v1/dictation/trigger`, since that endpoint
is a toggle: firing it while a recording is already running stops that
recording instead of starting a new one, which is rarely what a script
actually wants. Poll this endpoint (or check it once before triggering) to
decide which behaviour you'll get.

**Request body:** none.

**Responses:**

| Status | Body | Meaning |
| --- | --- | --- |
| 200 | `{"phase": "idle", "busy": false}` | No recording/transcription in progress; the next trigger call starts one |
| 200 | `{"phase": "recording", "busy": true}` | Actively recording audio; the next trigger call stops it |
| 200 | `{"phase": "transcribing", "busy": true}` | Recording stopped, transcription is running; the next trigger call is ignored until this settles (mirrors the hotkey's own behaviour) |
| 200 | `{"phase": "refining", "busy": true}` | Smart Mode's cleanup pass is running on the transcript; same "next trigger is ignored for now" note as `transcribing` |
| 200 | `{"phase": "done", "busy": false}` | The last recording just finished; the next trigger call starts a fresh one |
| 200 | `{"phase": "error", "busy": false}` | The last recording failed; the next trigger call starts a fresh one |
| 401 | `{"error": "unauthorized"}` | Missing/invalid bearer token |

```bash
curl http://127.0.0.1:8765/v1/dictation/status \
  -H "Authorization: Bearer <TOKEN>"
```

### `GET /v1/history/latest`

Returns the most recently transcribed history entry (same ordering as the
History page: pinned first, then newest timestamp).

**Request body:** none.

**Responses:**

| Status | Body | Meaning |
| --- | --- | --- |
| 200 | `{"id", "title", "content", "timestamp", "tags"}` | The latest entry |
| 401 | `{"error": "unauthorized"}` | Missing/invalid bearer token |
| 404 | `{"error": "no_history_entry"}` | No history entry exists yet |
| 423 | `{"error": "history_locked"}` | The history is protected by a PIN and currently locked — unlock it in the app first |
| 500 | `{"error": "fetch_failed"}` | Reading history threw an exception |

```bash
curl http://127.0.0.1:8765/v1/history/latest \
  -H "Authorization: Bearer <TOKEN>"
```

### `POST /v1/snippets/insert`

Looks up a saved snippet by its exact title and inserts it — the same
lookup-and-paste path the Snippet Picker itself uses when you pick a
snippet. Only `static` snippets are supported; `interactive` snippets (the
guided, multi-field recording sequence) can't be inserted headlessly.

**Request body:**

```json
{ "name": "<snippet title>" }
```

**Responses:**

| Status | Body | Meaning |
| --- | --- | --- |
| 200 | `{"status": "inserted"}` | Snippet was found and inserted |
| 400 | `{"error": "invalid_request"}` | Body is missing, not JSON, or `name` isn't a non-empty string |
| 401 | `{"error": "unauthorized"}` | Missing/invalid bearer token |
| 404 | `{"error": "snippet_not_found"}` | No snippet with that name exists |
| 409 | `{"error": "snippet_not_static"}` | The snippet exists but is `interactive` (unsupported headlessly) |
| 500 | `{"error": "insert_failed"}` | Insert/paste threw an exception |

```bash
curl -X POST http://127.0.0.1:8765/v1/snippets/insert \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name": "My Snippet"}'
```

### Multiline text needs confirmation

`POST /v1/snippets/insert` and any snippet whose body contains a line break
wait for you. WhisPaste shows the text in the main window with its line count
(bringing the window forward first if it is hidden or minimized), and only
inserts it after you press **Insert**. **Cancel**, Escape, closing the
dialog, or 60 seconds without an answer all cancel the request. A cancelled
request returns `409 {"error": "preview_cancelled"}` and nothing is pasted.
A second multiline request while one is still open is refused at once.

Inserting text uses the existing paste path, the same one the Snippet Picker
uses. That path sends the paste shortcut (Cmd+V / Ctrl+V) to the captured
target app. This is the one place where the API causes a keystroke. It is kept
as it was before the integrations work. The API never sends Enter or other
keystrokes of its own, the new endpoints send none, and it never runs a shell
command. The paste lands in the app that was captured when the last recording
or Side Panel opened; the API does not capture a new target itself.

### `GET /v1/status`

Returns the API version, the dictation status (the same object as
`GET /v1/dictation/status`) and whether the history is locked.

```json
{ "api_version": 1, "dictation": { … }, "history_locked": false }
```

### `GET /v1/notes?limit=N`

Lists notes, newest and pinned first. `limit` is 1 to 200 (default 50).

```json
{ "notes": [ { "id": "…", "content": "…", "pinned": false, "updated_at": "…" } ] }
```

### `POST /v1/notes`

Creates a note with the given text. Body: `{"content": "<text>"}`, at most
100 000 characters. Answers `201` with the note. Writes made through the API do
not fire the `note.changed` hook, so a hook cannot trigger itself.

### `GET /v1/snippets`

Lists snippets by title with their kind and field names.

```json
{ "snippets": [ { "name": "Greeting", "kind": "static", "fields": [] } ] }
```

### `POST /v1/snippets/render`

Renders a snippet with field values and returns the text. Nothing is pasted.
Body: `{"name": "<title>", "values": {"<field>": "<value>"}}`. Values are
inserted once and are not expanded again. Missing or unknown fields give
`400` with `missing_fields` or `unknown_fields` plus the field names.

### `POST /v1/transcriptions`

Transcribes one audio file. The body is the raw WAV file, sent with
`Content-Type: audio/wav`. Only 16 kHz, mono, 16-bit PCM WAV is accepted; other
formats get `415 {"error": "unsupported_format", "reason": "…"}`. The body limit
is 64 MiB. Answers `200 {"transcript": "…"}`. Other JSON endpoints accept at
most 64 KiB.

Dictation has priority. While a recording or a transcription is running, the
endpoint answers `409 {"error": "busy"}` and does not queue the upload. The CLI
reports this as a message and exits with status 1.

### Errors shared by all endpoints

| Status | Body | Meaning |
| --- | --- | --- |
| 401 | `{"error": "unauthorized"}` | Missing or wrong token |
| 403 | — | `Host` header is not a loopback name |
| 409 | `{"error": "busy"}` | Only `POST /v1/transcriptions`: a dictation is running |
| 413 | `{"error": "payload_too_large"}` | Body is over the endpoint's limit |

## Event hooks

WhisPaste can POST a JSON event to up to eight URLs you configure under
**Settings → Local Automation API → Integrations → Event hooks**.

Hooks are independent of the API switch. Once at least one hook is saved, it
fires even when the local API server is off, and a fired event leaves the app
without the token or any other secret.

- **Events:** `transcript.finished` (after a dictation, with `transcript` and
  `origin`) and `note.changed` (after a note is saved in the app, with
  `note_id` and `content`).
- **Targets:** only `http` URLs on a loopback address: `127.0.0.0/8` as a
  dotted-quad literal, `[::1]`, or exactly `localhost`. Decimal, hex and
  shortened IPv4 forms, IPv4-mapped IPv6, `localhost.example.com` and URLs with
  a user part are refused when you save them. `localhost` is checked again at
  send time and must resolve only to loopback addresses; the connection is then
  pinned to that address. Redirects are not followed.
- **Payload:** `Content-Type: application/json`, body
  `{"schema": "whispaste.automation-event", "version": 1, "event": "…", "occurred_at": "…", "data": {…}}`.
- **Delivery:** 3 second timeout. A timeout, network error or 5xx answer is
  retried once after 500 ms. Other failures are logged without the full URL.

## Command-line interface

`tool/whispaste.dart` talks to a running app over the same API. It is available
in source checkouts (`dart run tool/whispaste.dart <command>`) and is not part of
the store builds.

```bash
export WHISPASTE_API_TOKEN=<TOKEN>      # required; the port defaults to 8765
dart run tool/whispaste.dart status
dart run tool/whispaste.dart note create "Buy milk"
dart run tool/whispaste.dart note list --limit 10
dart run tool/whispaste.dart snippet list
dart run tool/whispaste.dart snippet render Greeting --field name=Ada
dart run tool/whispaste.dart transcribe clip.wav
```

`--port N` or `WHISPASTE_API_PORT` select another port. The token is read only
from the environment, so it does not appear in the command line.

## MCP server

`dart run tool/whispaste.dart mcp` runs a stdio MCP server (protocol revision
2025-03-26, tools only). Point an MCP client at it with the token in the
environment:

```json
{
  "mcpServers": {
    "whispaste": {
      "command": "dart",
      "args": ["run", "tool/whispaste.dart", "mcp"],
      "cwd": "/path/to/whispaste",
      "env": { "WHISPASTE_API_TOKEN": "<TOKEN>" }
    }
  }
}
```

Tools: `notes_list`, `notes_create`, `snippets_list`, `snippets_render`,
`last_dictation` and `trigger_dictation`. Diagnostics go to stderr only.

## Security

- **Loopback-only** — the server binds exclusively to `127.0.0.1` and `::1`.
  It is never bound to a wildcard or public interface, and there is no
  setting to change that. No other machine on your network can ever reach
  it.
- **Token-gated, no localhost exception** — every request, including one
  from `localhost`, must present the correct bearer token. Being on the
  same machine is not by itself enough to distinguish WhisPaste's own script
  user from any other local process.
- **Token rotation** — regenerate the token any time from Settings; the
  previous token stops working immediately, with no server restart
  required.
- **Off by default** — the API only starts once you explicitly enable it in
  Settings.

See [`NETWORK.md`](./NETWORK.md) for WhisPaste's full list of network
connections, and [`SECURITY.md`](./SECURITY.md) for how to report a
vulnerability.
