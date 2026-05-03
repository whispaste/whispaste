// crash-relay — tombstone endpoint.
//
// The old crash-relay + Discord pipeline was replaced by Sentry in v1.2.x.
// Old app builds (pre-v1.2.x) still POST here via a 60s SQLite queue flush.
// The old flush code only deletes queue items on 2xx — non-2xx keeps them in
// the queue and retries forever. Returning 200 drains the queue on every old
// build, stopping the retry loop that caused ~800k invocations/month.

Deno.serve((_req) => {
  return new Response(
    JSON.stringify({ ok: true, message: "crash-relay is deprecated — use Sentry SDK" }),
    {
      status: 200,
      headers: {
        "content-type": "application/json",
      },
    },
  );
});
