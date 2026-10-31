# Clipboard snapshot benchmark (Linux)

Measures what the full clipboard backup around a paste (P1.1) costs, compared with
the former plain-text read. Source: `clipboard_snapshot_bench.cc`, entry point
`clipboard_snapshot_bench.sh`. It is not part of `test/` and nothing asserts on
the numbers: it prints a table and exits 0 unless a case cannot run.

## Run

On a Linux machine with `libgtk-3-dev` and `xvfb`:

```bash
bash benchmarks/paste/clipboard_snapshot_bench.sh        # 30 iterations per case
bash benchmarks/paste/clipboard_snapshot_bench.sh 60     # more iterations
```

Runs on a private Xvfb display with `GDK_BACKEND=x11`. Start it on an idle machine;
other load shifts the numbers.

## What is measured

Each case is put on the clipboard by a second process (the owner), as another app
would. The benchmark then measures, per case:

- **VORHER:** `gtk_clipboard_wait_for_text`, the text form only (former path).
- **NACHHER snapshot:** `ClipboardSnapshot::Take` until its callback fires, with
  every offered target fetched.
- **NACHHER restore:** `ClipboardSnapshot::Restore`, which hands the data back to GTK.

Before each NACHHER iteration the owner takes the clipboard again, outside the
timing. Three warm-up iterations are dropped. Output is median and p95 (nearest
rank) in milliseconds, plus how many snapshots were saved, the number of formats
and the size in KiB.

Cases: `text-small` (one short sentence), `text-100kb`, `html+text` (8 KiB HTML and
about 1 KiB text), `png-1mb+text` and `png-8mb+text` (incompressible bytes with a PNG
signature, plus a short text).

## Limits

- Xvfb is an X server without a compositor or a real session. Wayland desktops reach
  the clipboard through a different path (the compositor, Klipper or wl-clipboard),
  so the numbers do not transfer to a Wayland session.
- The owner is a process of this benchmark, not a real application. Real apps can
  answer slower, for example when they render content lazily.
- Each case runs one owner; the 1.5 s snapshot budget and the 64 MiB byte cap in
  `clipboard_snapshot.cc` are the production values. A `failed` status in a row
  means the budget or cap was hit and the numbers for that case are not complete.
