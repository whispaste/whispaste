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

Triggers dictation — the same action as pressing the global hotkey.

**Request body:** none.

**Responses:**

| Status | Body | Meaning |
| --- | --- | --- |
| 200 | `{"status": "triggered"}` | Dictation was triggered |
| 401 | `{"error": "unauthorized"}` | Missing/invalid bearer token |
| 500 | `{"error": "trigger_failed"}` | Triggering dictation threw an exception |

```bash
curl -X POST http://127.0.0.1:8765/v1/dictation/trigger \
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
