/// HTML report renderer for WhisPaste GPU-Probe results.
///
/// Produces a self-contained `<!DOCTYPE html>` document with all CSS (and, in
/// live mode, all JS) inlined. No external resources, no CDN references, no JS
/// frameworks — the report opens straight from `file://` or the local server.
///
/// Aesthetic: a dark "instrument / telemetry readout" — monospace-forward,
/// signal-lime accent for speed, tabular numerics, a relative-speed bar viz,
/// and a staggered load reveal.
library;

import 'brand_assets.dart';
import 'probe_types.dart';
import 'ranking.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Renders [report] as a self-contained HTML document (German UI, UTF-8).
///
/// When [live] is true the ranking rows gain a "Live testen" action and the
/// document embeds the microphone-test JavaScript that talks to the local
/// probe server; [token] is the per-session token appended to every API call.
/// In static mode (the on-disk / ZIP artifact) no JS and no buttons are
/// emitted so the saved file stays a clean record.
String formatProbeReportHtml(
  ProbeReport report, {
  bool live = false,
  String? token,
}) {
  final ranking = computeRanking(report);
  final b = StringBuffer();

  // Find the best non-baseline ok candidate (winner).
  RankedCandidate? winner;
  for (final rc in ranking.ranked) {
    if (!rc.isCpuBaseline) {
      winner = rc;
      break;
    }
  }

  // Highest speedup among ranked rows — used to scale the relative-speed bars.
  var maxSpeedup = 1.0;
  for (final rc in ranking.ranked) {
    if (rc.speedupFactor > maxSpeedup) maxSpeedup = rc.speedupFactor;
  }

  b.writeln('<!DOCTYPE html>');
  b.writeln('<html lang="de">');
  b.writeln('<head>');
  b.writeln('<meta charset="utf-8">');
  b.writeln(
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
  );
  b.writeln('<title>WhisPaste GPU-Probe Report</title>');
  b.writeln(_css);
  b.writeln('</head>');
  b.writeln('<body>');
  _writeHeader(b, report, live: live);
  b.writeln('<main class="container">');
  _writeBaselineMissingWarning(b, ranking);
  _writeWinnerBanner(b, ranking, winner);
  if (live) _writeLivePanel(b);
  _writeRankingTable(b, ranking, winner, maxSpeedup, live: live);
  _writeFailedSection(b, ranking);
  _writeHardwareSection(b, report);
  b.writeln('</main>');
  _writeFooter(b, report, live: live);
  if (live) {
    b.writeln(_liveScript.replaceAll('__TOKEN__', token ?? ''));
  }
  b.writeln('</body>');
  b.write('</html>');

  return b.toString();
}

/// A single candidate row for the progress shell, before results exist.
typedef ProgressCandidate = ({String id, String label});

/// Renders the "Analyse läuft…" progress shell served while the probe runs.
///
/// The page lists every [candidates] entry with a live status dot, an elapsed
/// timer, and subscribes to the server's `/events` SSE stream. On the `done`
/// event it reloads, at which point the server serves the finished report.
/// [token] is appended to the SSE/API calls.
String formatProgressShellHtml({
  required List<ProgressCandidate> candidates,
  required String version,
  required DateTime timestamp,
  String? token,
}) {
  final b = StringBuffer();
  b.writeln('<!DOCTYPE html>');
  b.writeln('<html lang="de">');
  b.writeln('<head>');
  b.writeln('<meta charset="utf-8">');
  b.writeln(
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
  );
  b.writeln('<title>WhisPaste GPU-Probe Report — Analyse läuft</title>');
  b.writeln(_css);
  b.writeln('</head>');
  b.writeln('<body>');

  b.writeln('<header class="site-header">');
  b.writeln(
    '  <span class="brand">'
    '<img class="brand-logo" alt="WhisPaste" src="$whispasteLogoDataUri">'
    ' WhisPaste GPU-Probe Report</span>',
  );
  b.writeln(
    '  <span class="header-meta">v${_esc(version)}'
    ' &nbsp;·&nbsp; ${_esc(timestamp.toIso8601String())}</span>',
  );
  b.writeln('</header>');

  b.writeln('<main class="container">');
  b.writeln('<section class="run-hero reveal">');
  b.writeln(
    '  <div class="run-pulse" aria-hidden="true">'
    '<span></span><span></span><span></span></div>',
  );
  b.writeln('  <h1 class="run-title">Analyse läuft</h1>');
  b.writeln(
    '  <p class="run-sub">Die Engines werden nacheinander auf deiner '
    'Hardware getestet. Das kann ein paar Minuten dauern — du musst nichts '
    'tun, der Report öffnet sich danach automatisch hier.</p>',
  );
  b.writeln(
    '  <div class="run-elapsed">Laufzeit '
    '<span id="elapsed" class="mono">0:00</span></div>',
  );
  b.writeln('</section>');

  b.writeln('<section class="reveal" style="animation-delay:.08s">');
  b.writeln('<h2>Kandidaten</h2>');
  b.writeln('<ul class="run-list" id="run-list">');
  for (final c in candidates) {
    b.writeln(
      '  <li class="run-item" data-cand="${_esc(c.id)}" '
      'data-state="pending">',
    );
    b.writeln('    <span class="run-dot" aria-hidden="true"></span>');
    b.writeln('    <span class="run-name">${_esc(c.label)}</span>');
    b.writeln('    <span class="run-status mono">wartet</span>');
    b.writeln('  </li>');
  }
  b.writeln('</ul>');
  b.writeln('</section>');
  b.writeln('</main>');

  b.writeln(
    '<footer class="site-footer">'
    'WhisPaste GPU-Probe v${_esc(version)} &nbsp;·&nbsp; '
    'Analyse läuft…</footer>',
  );

  b.writeln(_progressScript.replaceAll('__TOKEN__', token ?? ''));
  b.writeln('</body>');
  b.write('</html>');
  return b.toString();
}

// ---------------------------------------------------------------------------
// Section helpers
// ---------------------------------------------------------------------------

void _writeHeader(StringBuffer b, ProbeReport report, {required bool live}) {
  b.writeln('<header class="site-header reveal">');
  b.writeln(
    '  <span class="brand">'
    '<img class="brand-logo" alt="WhisPaste" src="$whispasteLogoDataUri">'
    ' WhisPaste GPU-Probe Report</span>',
  );
  b.writeln(
    '  <span class="header-meta">v${_esc(report.version)}'
    ' &nbsp;·&nbsp; ${_esc(report.timestamp.toIso8601String())}'
    '${live ? ' &nbsp;·&nbsp; <span class="live-tag">LIVE</span>' : ''}'
    '</span>',
  );
  b.writeln('</header>');
}

void _writeBaselineMissingWarning(StringBuffer b, RankingResult ranking) {
  if (!ranking.cpuBaselineMissing) return;
  b.writeln('<div class="banner banner-warn reveal">');
  b.writeln(
    '  <strong>⚠ Warnung:</strong> Kein CPU-Baseline-Kandidat gefunden '
    '(ID-Präfix <code>whisper-cpp-cpu</code> oder Backend <code>cpu</code>). '
    'Speedup-Faktoren können nicht berechnet werden.',
  );
  b.writeln('</div>');
}

void _writeWinnerBanner(
  StringBuffer b,
  RankingResult ranking,
  RankedCandidate? winner,
) {
  if (winner != null) {
    _writeWinnerFound(b, winner);
  } else if (!ranking.cpuBaselineMissing) {
    b.writeln('<div class="banner banner-info reveal">');
    b.writeln(
      '  Keine lauffähige GPU-Lösung gefunden — '
      'die CPU-Baseline bleibt die beste Option.',
    );
    b.writeln('</div>');
  }
}

void _writeWinnerFound(StringBuffer b, RankedCandidate winner) {
  final speedupStr = _formatSpeedupDe(winner.speedupFactor);
  final werStr = _formatWerDe(winner.result.wer);
  final latMs = winner.result.durationMs;
  final latStr = latMs != null ? _formatMs(latMs) : '—';
  final label = _candidateLabel(winner.result);

  b.writeln('<section class="winner reveal">');
  b.writeln('  <div class="winner-flag">★ Beste lauffähige GPU-Option</div>');
  b.writeln('  <div class="winner-grid">');
  b.writeln('    <div class="winner-id">${_esc(label)}</div>');
  b.writeln('    <div class="winner-big">');
  b.writeln('      <span class="winner-big-num">${_esc(speedupStr)}</span>');
  b.writeln('      <span class="winner-big-cap">schneller als CPU</span>');
  b.writeln('    </div>');
  b.writeln('  </div>');
  b.writeln('  <div class="winner-stats">');
  _writeStat(b, 'Latenz', latStr);
  _writeStat(b, 'Wortfehlerrate', werStr);
  _writeStat(
    b,
    'Realtime-Faktor',
    winner.result.realtimeFactor != null
        ? winner.result.realtimeFactor!.toStringAsFixed(2)
        : '—',
  );
  b.writeln('  </div>');
  b.writeln('</section>');
}

void _writeStat(StringBuffer b, String label, String value) {
  b.writeln(
    '    <span class="stat"><span class="stat-label">${_esc(label)}'
    '</span><span class="stat-value mono">${_esc(value)}</span></span>',
  );
}

void _writeRankingTable(
  StringBuffer b,
  RankingResult ranking,
  RankedCandidate? winner,
  double maxSpeedup, {
  required bool live,
}) {
  if (ranking.ranked.isEmpty) return;
  b.writeln('<section class="reveal" style="animation-delay:.06s">');
  b.writeln('<h2>Geschwindigkeits-Ranking</h2>');
  b.writeln('<div class="table-wrap">');
  b.writeln('<table>');
  b.writeln('<thead><tr>');
  b.writeln('  <th class="col-rank">#</th>');
  b.writeln('  <th>Kandidat</th>');
  b.writeln('  <th>Ergebnis</th>');
  b.writeln('  <th class="num">Latenz</th>');
  b.writeln('  <th class="num">RT-Faktor</th>');
  b.writeln('  <th>Tempo vs. CPU</th>');
  b.writeln('  <th class="num">WER</th>');
  if (live) b.writeln('  <th class="col-live">Live-Test</th>');
  b.writeln('</tr></thead>');
  b.writeln('<tbody>');
  for (var i = 0; i < ranking.ranked.length; i++) {
    _writeRankingRow(
      b,
      ranking.ranked[i],
      i + 1,
      winner,
      maxSpeedup,
      live: live,
    );
  }
  b.writeln('</tbody>');
  b.writeln('</table>');
  b.writeln('</div>');
  b.writeln('</section>');
}

void _writeRankingRow(
  StringBuffer b,
  RankedCandidate rc,
  int rank,
  RankedCandidate? winner,
  double maxSpeedup, {
  required bool live,
}) {
  final isWinner =
      winner != null && rc.result.candidateId == winner.result.candidateId;
  final rowClass = StringBuffer('');
  if (rc.isCpuBaseline) rowClass.write(' row-baseline');
  if (isWinner) rowClass.write(' row-winner');

  final durStr = rc.result.durationMs != null
      ? _formatMs(rc.result.durationMs!)
      : '—';
  final rtfStr = rc.result.realtimeFactor != null
      ? rc.result.realtimeFactor!.toStringAsFixed(2)
      : '—';
  final speedStr = _formatSpeedupDe(rc.speedupFactor);
  final werStr = _formatWerDe(rc.result.wer);
  final label = rc.isCpuBaseline
      ? '${_esc(_candidateLabel(rc.result))} '
            '<span class="badge-baseline">Baseline</span>'
      : _esc(_candidateLabel(rc.result));

  // Relative-speed bar width (0–100 %), scaled to the fastest candidate.
  final pct = maxSpeedup > 0 && rc.speedupFactor > 0
      ? (rc.speedupFactor / maxSpeedup * 100).clamp(2.0, 100.0)
      : 0.0;
  final barClass = isWinner ? 'bar bar-winner' : 'bar';

  b.writeln('<tr class="${rowClass.toString().trim()}">');
  b.writeln('  <td class="col-rank rank">$rank</td>');
  b.writeln('  <td class="candidate-name">$label</td>');
  b.writeln('  <td><span class="badge outcome-ok">ok</span></td>');
  b.writeln('  <td class="num mono">${_esc(durStr)}</td>');
  b.writeln('  <td class="num mono">${_esc(rtfStr)}</td>');
  b.writeln('  <td class="speed-cell">');
  b.writeln(
    '    <span class="bar-track"><span class="$barClass" '
    'style="width:${pct.toStringAsFixed(1)}%"></span></span>',
  );
  b.writeln('    <span class="speedup mono">${_esc(speedStr)}</span>');
  b.writeln('  </td>');
  b.writeln('  <td class="num mono">${_esc(werStr)}</td>');
  if (live) {
    b.writeln(
      '  <td class="col-live"><button type="button" class="live-btn" '
      'data-cand="${_esc(rc.result.candidateId)}" '
      'data-label="${_esc(_candidateLabel(rc.result))}">'
      '● Live testen</button></td>',
    );
  }
  b.writeln('</tr>');
}

void _writeLivePanel(StringBuffer b) {
  b.writeln('<section class="live-panel reveal" id="live-panel" hidden>');
  b.writeln('  <div class="live-head">');
  b.writeln('    <h2>Live-Mikrofon-Test</h2>');
  b.writeln('    <span class="live-cand mono" id="live-cand">—</span>');
  b.writeln('  </div>');
  b.writeln(
    '  <p class="live-hint">Sprich einen Satz ein. Das Tool jagt deine '
    'Aufnahme durch die gewählte Engine und misst, wie lange es vom Ende des '
    'Sprechens bis zum fertigen Text dauert.</p>',
  );
  b.writeln('  <div class="live-controls">');
  b.writeln(
    '    <button type="button" class="rec-btn" id="rec-btn" disabled>'
    '● Aufnahme starten</button>',
  );
  b.writeln(
    '    <span class="rec-state mono" id="rec-state">'
    'Kandidat oben wählen</span>',
  );
  b.writeln('  </div>');
  b.writeln('  <div class="live-result" id="live-result" hidden>');
  b.writeln('    <div class="live-metrics">');
  b.writeln(
    '      <span class="stat"><span class="stat-label">'
    'Sprech-Ende → Text</span>'
    '<span class="stat-value mono" id="m-total">—</span></span>',
  );
  b.writeln(
    '      <span class="stat"><span class="stat-label">'
    'Engine-Verarbeitung</span>'
    '<span class="stat-value mono" id="m-engine">—</span></span>',
  );
  b.writeln(
    '      <span class="stat"><span class="stat-label">'
    'Aufnahme-Länge</span>'
    '<span class="stat-value mono" id="m-audio">—</span></span>',
  );
  b.writeln(
    '      <span class="stat"><span class="stat-label">'
    'Realtime-Faktor</span>'
    '<span class="stat-value mono" id="m-rtf">—</span></span>',
  );
  b.writeln('    </div>');
  b.writeln('    <div class="live-transcript-label">Transkript</div>');
  b.writeln(
    '    <blockquote class="live-transcript" id="m-text">—'
    '</blockquote>',
  );
  b.writeln('  </div>');
  b.writeln('</section>');
}

void _writeFailedSection(StringBuffer b, RankingResult ranking) {
  if (ranking.failed.isEmpty) return;
  b.writeln('<section class="reveal" style="animation-delay:.1s">');
  b.writeln('<h2>Nicht lauffähige Kandidaten</h2>');
  b.writeln('<div class="table-wrap">');
  b.writeln('<table>');
  b.writeln('<thead><tr>');
  b.writeln('  <th>Kandidat</th>');
  b.writeln('  <th>Ergebnis</th>');
  b.writeln('  <th>Detail</th>');
  b.writeln('</tr></thead>');
  b.writeln('<tbody>');
  for (final r in ranking.failed) {
    _writeFailedRow(b, r);
  }
  b.writeln('</tbody>');
  b.writeln('</table>');
  b.writeln('</div>');
  b.writeln('</section>');
}

void _writeFailedRow(StringBuffer b, CandidateResult r) {
  final outcomeClass = _outcomeClass(r.outcome);
  final outcomeLabel = _outcomeLabel(r.outcome);
  final detail = r.errorDetail ?? r.stderrTail ?? '—';

  b.writeln('<tr>');
  b.writeln('  <td class="candidate-name">${_esc(r.candidateId)}</td>');
  b.writeln(
    '  <td><span class="badge $outcomeClass">'
    '${_esc(outcomeLabel)}</span></td>',
  );
  b.writeln('  <td class="error-detail mono">${_esc(detail)}</td>');
  b.writeln('</tr>');
}

void _writeHardwareSection(StringBuffer b, ProbeReport report) {
  if (report.hardwareContext == null) return;
  final hw = report.hardwareContext!;
  b.writeln('<section class="reveal" style="animation-delay:.14s">');
  b.writeln('<h2>Hardware-Kontext</h2>');
  b.writeln('<dl class="hw-grid">');
  if (hw.gpuModel != null) {
    b.writeln('  <dt>GPU</dt><dd>${_esc(hw.gpuModel!)}</dd>');
  }
  if (hw.vramGb != null) {
    b.writeln('  <dt>VRAM</dt><dd>${_esc('${hw.vramGb} GB')}</dd>');
  }
  if (hw.cpuModel != null) {
    b.writeln('  <dt>CPU</dt><dd>${_esc(hw.cpuModel!)}</dd>');
  }
  if (hw.ramGb != null) {
    b.writeln('  <dt>RAM</dt><dd>${_esc('${hw.ramGb} GB')}</dd>');
  }
  if (hw.os != null) {
    b.writeln('  <dt>OS</dt><dd>${_esc(hw.os!)}</dd>');
  }
  if (hw.driverVersion != null) {
    b.writeln('  <dt>Treiber</dt><dd>${_esc(hw.driverVersion!)}</dd>');
  }
  b.writeln('</dl>');
  b.writeln('</section>');
}

void _writeFooter(StringBuffer b, ProbeReport report, {required bool live}) {
  b.writeln('<footer class="site-footer">');
  if (live) {
    b.writeln(
      '  <button type="button" class="quit-btn" id="quit-btn">'
      'Tool beenden</button>',
    );
  }
  b.writeln(
    '  <span class="footer-meta">WhisPaste GPU-Probe v${_esc(report.version)}'
    ' &nbsp;·&nbsp; ${_esc(report.timestamp.toIso8601String())}</span>',
  );
  b.writeln('</footer>');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// HTML-escapes [text] to prevent injection.
String _esc(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Builds a display label for a candidate using engine/backend/model fields.
String _candidateLabel(CandidateResult r) {
  final parts = <String>[r.candidateId];
  if (r.backend != null && r.backend != r.candidateId) {
    parts.add('(${r.backend}');
    if (r.modelId != null) {
      parts.last += ', ${r.modelId}';
    }
    parts.last += ')';
  } else if (r.modelId != null) {
    parts.add('(${r.modelId})');
  }
  return parts.join(' ');
}

/// Formats a millisecond duration as a compact human string: `8000` → `8,0 s`,
/// `420` → `420 ms`.
String _formatMs(int ms) {
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';
}

/// Formats speedup factor in German locale notation, e.g. `6,0×`.
String _formatSpeedupDe(double factor) {
  if (factor == 0.0) return 'n/a';
  return '${factor.toStringAsFixed(1).replaceAll('.', ',')}×';
}

/// Formats WER as a German percentage string, e.g. `8,0 %`.
String _formatWerDe(double? wer) {
  if (wer == null) return '—';
  return '${(wer * 100).toStringAsFixed(1).replaceAll('.', ',')} %';
}

/// Returns the CSS class name for an outcome badge.
String _outcomeClass(Outcome outcome) {
  return switch (outcome) {
    Outcome.ok => 'outcome-ok',
    Outcome.crashed => 'outcome-crashed',
    Outcome.failedToStart => 'outcome-crashed',
    Outcome.outOfMemory => 'outcome-crashed',
    Outcome.hung => 'outcome-hung',
    Outcome.wrongOutput => 'outcome-hung',
    Outcome.skipped => 'outcome-skipped',
  };
}

/// Returns a short German display label for an outcome.
String _outcomeLabel(Outcome outcome) {
  return switch (outcome) {
    Outcome.ok => 'ok',
    Outcome.crashed => 'abgestürzt',
    Outcome.failedToStart => 'Startfehler',
    Outcome.outOfMemory => 'OOM',
    Outcome.hung => 'hängt',
    Outcome.wrongOutput => 'falsches Ergebnis',
    Outcome.skipped => 'übersprungen',
  };
}

// ---------------------------------------------------------------------------
// Inline CSS — dark "telemetry / instrument" theme
// ---------------------------------------------------------------------------

const String _css = '''
<style>
  :root {
    /* WhisPaste brand palette — mirrors lib/core/theme/colors.dart (dark). */
    --bg: #131826;          /* background */
    --bg-2: #171d2c;        /* surface */
    --panel: #1d2538;       /* surfaceElevated */
    --panel-2: #232c40;     /* surfaceVariant */
    --line: rgba(255,255,255,.19);      /* borderDefault */
    --line-soft: rgba(255,255,255,.12); /* borderSubtle */
    --txt: #f0f4fa;         /* textPrimary */
    --muted: #8a99b2;       /* textMuted */
    --faint: #5b6b85;
    --signal: #38d9f0;      /* accent — vibrant cyan */
    --signal-dim: #14b8d4;  /* teal (accentWarmGradient mid) */
    --green: #36d98b;       /* success */
    --cyan: #38d9f0;
    --amber: #f5c842;       /* warning */
    --red: #ff7b7b;         /* error */
    --mono: "Cascadia Code", "JetBrains Mono", "SF Mono", "Fira Code",
            ui-monospace, Menlo, Consolas, monospace;
    --sans: "Segoe UI Variable Display", "Segoe UI", system-ui,
            -apple-system, "Helvetica Neue", sans-serif;
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: var(--sans);
    font-size: 14px;
    color: var(--txt);
    line-height: 1.6;
    background-color: var(--bg);
    background-image:
      radial-gradient(1100px 520px at 78% -8%, rgba(56,217,240,.10), transparent 60%),
      radial-gradient(900px 480px at 8% 0%, rgba(56,217,240,.07), transparent 55%),
      linear-gradient(transparent 0 31px, rgba(255,255,255,.018) 31px 32px),
      linear-gradient(90deg, transparent 0 31px, rgba(255,255,255,.018) 31px 32px);
    background-size: auto, auto, 32px 32px, 32px 32px;
    background-attachment: fixed;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }
  .mono { font-family: var(--mono); font-variant-numeric: tabular-nums; }

  /* ── Header / footer ─────────────────────────────────────────────────── */
  .site-header {
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; flex-wrap: wrap;
    padding: 16px 28px;
    border-bottom: 1px solid var(--line);
    background: linear-gradient(180deg, rgba(19,26,40,.9), rgba(10,14,22,.6));
    backdrop-filter: blur(6px);
    position: sticky; top: 0; z-index: 20;
  }
  .brand {
    display: inline-flex; align-items: center;
    font-size: 15px; font-weight: 700; letter-spacing: .04em;
  }
  .brand-logo {
    height: 26px; width: 26px; margin-right: 10px;
    filter: drop-shadow(0 0 10px rgba(56,217,240,.28));
  }
  .header-meta {
    font-family: var(--mono); font-size: 12px; color: var(--muted);
  }
  .live-tag {
    color: var(--bg); background: var(--signal); font-weight: 800;
    padding: 1px 7px; border-radius: 4px; letter-spacing: .12em; font-size: 10px;
  }
  .site-footer {
    display: flex; align-items: center; justify-content: space-between;
    gap: 16px; flex-wrap: wrap;
    max-width: 1080px; margin: 40px auto 0; padding: 22px 24px;
    border-top: 1px solid var(--line);
    font-size: 11px; color: var(--muted); font-family: var(--mono);
  }
  .footer-meta { margin-left: auto; }

  /* ── Layout ──────────────────────────────────────────────────────────── */
  .container {
    max-width: 1080px; margin: 34px auto; padding: 0 24px;
    display: flex; flex-direction: column; gap: 30px;
  }
  section h2 {
    font-family: var(--mono);
    font-size: 12px; font-weight: 700; color: var(--muted);
    text-transform: uppercase; letter-spacing: .18em;
    margin-bottom: 16px; padding-bottom: 10px;
    border-bottom: 1px solid var(--line-soft);
  }
  section h2::before { content: "// "; color: var(--signal-dim); }

  /* ── Banners ─────────────────────────────────────────────────────────── */
  .banner {
    border-radius: 12px; padding: 16px 20px; border: 1px solid var(--line);
    border-left-width: 4px; background: var(--panel);
  }
  .banner code {
    background: rgba(255,255,255,.06); padding: 1px 6px; border-radius: 4px;
    font-family: var(--mono); font-size: 12px;
  }
  .banner-warn { border-left-color: var(--amber); color: #fde9bf; }
  .banner-warn strong { color: var(--amber); }
  .banner-info { border-left-color: var(--cyan); color: #cfeafe; }

  /* ── Winner readout ──────────────────────────────────────────────────── */
  .winner {
    position: relative; overflow: hidden;
    border: 1px solid var(--signal-dim); border-radius: 16px;
    padding: 26px 28px;
    background:
      radial-gradient(640px 240px at 88% -40%, rgba(56,217,240,.18), transparent 70%),
      linear-gradient(180deg, var(--panel-2), var(--panel));
    box-shadow: 0 0 0 1px rgba(56,217,240,.08), 0 24px 60px -30px rgba(56,217,240,.25);
  }
  .winner-flag {
    font-family: var(--mono); font-size: 11px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .2em; color: var(--signal);
    margin-bottom: 14px;
  }
  .winner-grid {
    display: flex; align-items: flex-end; justify-content: space-between;
    gap: 20px; flex-wrap: wrap;
  }
  .winner-id {
    font-family: var(--mono); font-size: 22px; font-weight: 700;
    color: var(--txt); word-break: break-word;
  }
  .winner-big { display: flex; flex-direction: column; align-items: flex-end; }
  .winner-big-num {
    font-family: var(--mono); font-weight: 800; line-height: .9;
    font-size: clamp(44px, 9vw, 76px); color: var(--signal);
    text-shadow: 0 0 40px rgba(56,217,240,.35);
    font-variant-numeric: tabular-nums;
  }
  .winner-big-cap {
    font-size: 11px; text-transform: uppercase; letter-spacing: .16em;
    color: var(--muted); margin-top: 2px;
  }
  .winner-stats, .live-metrics {
    display: flex; flex-wrap: wrap; gap: 14px; margin-top: 22px;
  }
  .stat {
    display: flex; flex-direction: column; gap: 3px;
    background: rgba(255,255,255,.025); border: 1px solid var(--line-soft);
    border-radius: 10px; padding: 10px 14px; min-width: 130px; flex: 1;
  }
  .stat-label {
    font-size: 10px; text-transform: uppercase; letter-spacing: .12em;
    color: var(--muted); font-weight: 600;
  }
  .stat-value { font-size: 17px; font-weight: 700; color: var(--txt); }

  /* ── Tables ──────────────────────────────────────────────────────────── */
  .table-wrap {
    border: 1px solid var(--line); border-radius: 12px; overflow: hidden;
    background: var(--panel);
  }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  thead tr { background: var(--bg-2); }
  th {
    text-align: left; padding: 11px 16px; font-family: var(--mono);
    font-size: 10px; text-transform: uppercase; letter-spacing: .1em;
    color: var(--muted); font-weight: 700; white-space: nowrap;
    border-bottom: 1px solid var(--line);
  }
  th.num, td.num { text-align: right; }
  td {
    padding: 12px 16px; border-top: 1px solid var(--line-soft);
    vertical-align: middle;
  }
  tbody tr { transition: background .12s ease; }
  tbody tr:hover td { background: rgba(255,255,255,.022); }
  .row-baseline td { background: rgba(56,217,240,.05); }
  .row-winner td { background: rgba(56,217,240,.06); }
  .row-winner:hover td { background: rgba(56,217,240,.1); }
  .col-rank { width: 42px; text-align: center; }
  .rank {
    font-family: var(--mono); font-weight: 700; color: var(--muted);
    text-align: center;
  }
  .row-winner .rank { color: var(--signal); }
  .candidate-name { font-family: var(--mono); font-size: 12px; font-weight: 600; }
  .error-detail {
    font-size: 11px; color: var(--muted); max-width: 520px; word-break: break-word;
  }

  /* relative-speed bar */
  .speed-cell { min-width: 168px; }
  .bar-track {
    display: inline-block; vertical-align: middle; width: 96px; height: 7px;
    background: rgba(255,255,255,.07); border-radius: 99px; overflow: hidden;
    margin-right: 10px;
  }
  .bar {
    display: block; height: 100%; border-radius: 99px;
    background: linear-gradient(90deg, #3a4a66, #5b6b85);
    animation: grow .8s cubic-bezier(.2,.8,.2,1) both;
  }
  .bar-winner { background: linear-gradient(90deg, var(--signal-dim), var(--signal)); }
  .speedup { font-weight: 700; color: var(--txt); }
  .row-winner .speedup { color: var(--signal); }

  /* ── Badges ──────────────────────────────────────────────────────────── */
  .badge {
    display: inline-block; padding: 3px 9px; border-radius: 99px;
    font-family: var(--mono); font-size: 10px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .06em; border: 1px solid transparent;
  }
  .outcome-ok { background: rgba(54,217,139,.16); color: var(--green); border-color: rgba(54,217,139,.35); }
  .outcome-crashed { background: rgba(248,113,113,.14); color: var(--red); border-color: rgba(248,113,113,.3); }
  .outcome-hung { background: rgba(251,191,36,.14); color: var(--amber); border-color: rgba(251,191,36,.3); }
  .outcome-skipped { background: rgba(128,144,168,.14); color: var(--muted); border-color: rgba(128,144,168,.3); }
  .badge-baseline {
    display: inline-block; margin-left: 6px; padding: 1px 7px; border-radius: 4px;
    font-family: var(--mono); font-size: 9px; font-weight: 700;
    background: rgba(56,217,240,.15); color: var(--cyan);
    text-transform: uppercase; letter-spacing: .08em; vertical-align: middle;
  }

  /* ── Hardware grid ───────────────────────────────────────────────────── */
  .hw-grid {
    display: grid; grid-template-columns: max-content 1fr; gap: 1px;
    background: var(--line-soft); border: 1px solid var(--line);
    border-radius: 12px; overflow: hidden;
  }
  .hw-grid dt {
    font-family: var(--mono); font-size: 10px; font-weight: 700;
    text-transform: uppercase; letter-spacing: .1em; color: var(--muted);
    padding: 11px 16px; background: var(--bg-2);
  }
  .hw-grid dd {
    font-family: var(--mono); font-size: 12px; color: var(--txt);
    padding: 11px 16px; background: var(--panel);
  }

  /* ── Live test ───────────────────────────────────────────────────────── */
  .live-panel {
    border: 1px solid var(--line); border-radius: 16px; padding: 22px 24px;
    background: linear-gradient(180deg, var(--panel-2), var(--panel));
    scroll-margin-top: 80px;
  }
  .live-head { display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap; }
  .live-head h2 { border: 0; margin: 0; padding: 0; }
  .live-cand { color: var(--signal); font-size: 13px; }
  .live-hint { color: var(--muted); font-size: 13px; margin: 10px 0 18px; max-width: 70ch; }
  .live-controls { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
  .rec-btn {
    font-family: var(--mono); font-size: 14px; font-weight: 700; cursor: pointer;
    color: var(--bg); background: var(--signal); border: 0; border-radius: 10px;
    padding: 12px 20px; transition: transform .08s ease, filter .15s ease, background .15s;
  }
  .rec-btn:hover:not(:disabled) { filter: brightness(1.08); }
  .rec-btn:active:not(:disabled) { transform: translateY(1px); }
  .rec-btn:disabled { opacity: .4; cursor: not-allowed; }
  .rec-btn.recording { background: var(--red); color: #fff; animation: pulse 1.1s ease-in-out infinite; }
  .rec-btn.busy { background: var(--amber); }
  .rec-state { color: var(--muted); font-size: 13px; }
  .live-result { margin-top: 20px; border-top: 1px solid var(--line-soft); padding-top: 18px; }
  .live-transcript-label {
    font-family: var(--mono); font-size: 10px; text-transform: uppercase;
    letter-spacing: .12em; color: var(--muted); margin: 16px 0 6px;
  }
  .live-transcript {
    font-size: 16px; line-height: 1.55; color: var(--txt);
    border-left: 3px solid var(--signal); padding: 4px 0 4px 16px;
  }
  .live-btn {
    font-family: var(--mono); font-size: 11px; font-weight: 700; cursor: pointer;
    color: var(--signal); background: rgba(56,217,240,.08);
    border: 1px solid rgba(56,217,240,.3); border-radius: 8px; padding: 6px 12px;
    white-space: nowrap; transition: background .12s, transform .08s;
  }
  .live-btn:hover { background: rgba(56,217,240,.16); }
  .live-btn:active { transform: translateY(1px); }
  .col-live { text-align: right; }
  .quit-btn {
    font-family: var(--mono); font-size: 12px; cursor: pointer; color: var(--muted);
    background: transparent; border: 1px solid var(--line); border-radius: 8px;
    padding: 8px 16px; transition: color .15s, border-color .15s;
  }
  .quit-btn:hover { color: var(--red); border-color: rgba(248,113,113,.4); }

  /* ── Progress shell ──────────────────────────────────────────────────── */
  .run-hero { text-align: center; padding: 30px 20px 6px; }
  .run-pulse { display: flex; justify-content: center; gap: 8px; margin-bottom: 20px; }
  .run-pulse span {
    width: 10px; height: 36px; border-radius: 4px; background: var(--signal);
    animation: bounce 1s ease-in-out infinite; opacity: .85;
  }
  .run-pulse span:nth-child(2) { animation-delay: .15s; }
  .run-pulse span:nth-child(3) { animation-delay: .3s; }
  .run-title { font-size: 30px; font-weight: 800; letter-spacing: -.01em; }
  .run-sub { color: var(--muted); max-width: 60ch; margin: 10px auto 0; }
  .run-elapsed {
    margin-top: 20px; font-family: var(--mono); font-size: 13px; color: var(--muted);
  }
  .run-elapsed .mono { color: var(--signal); font-size: 17px; font-weight: 700; }
  .run-list { list-style: none; display: flex; flex-direction: column; gap: 1px;
    background: var(--line-soft); border: 1px solid var(--line);
    border-radius: 12px; overflow: hidden; }
  .run-item { display: flex; align-items: center; gap: 14px; padding: 13px 18px;
    background: var(--panel); }
  .run-dot { width: 11px; height: 11px; border-radius: 99px; flex-shrink: 0;
    background: var(--faint); box-shadow: 0 0 0 4px rgba(255,255,255,.03); }
  .run-item[data-state="running"] .run-dot { background: var(--amber);
    animation: pulse 1.1s ease-in-out infinite; }
  .run-item[data-state="ok"] .run-dot { background: var(--green); }
  .run-item[data-state="fail"] .run-dot { background: var(--red); }
  .run-item[data-state="skip"] .run-dot { background: var(--muted); }
  .run-name { font-family: var(--mono); font-size: 13px; flex: 1; }
  .run-item[data-state="pending"] .run-name { color: var(--muted); }
  .run-status { font-size: 11px; color: var(--muted); text-transform: uppercase;
    letter-spacing: .08em; }

  /* ── Motion ──────────────────────────────────────────────────────────── */
  @keyframes grow { from { width: 0 !important; } }
  @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: .55; } }
  @keyframes bounce { 0%,100% { transform: scaleY(.4); opacity: .5; }
    50% { transform: scaleY(1); opacity: 1; } }
  .reveal { animation: rise .5s cubic-bezier(.2,.8,.2,1) both; }
  @keyframes rise { from { opacity: 0; transform: translateY(10px); } }
  @media (prefers-reduced-motion: reduce) {
    .reveal, .bar, .run-pulse span, .rec-btn.recording,
    .run-item[data-state="running"] .run-dot { animation: none; }
  }
  @media (max-width: 680px) {
    .winner-grid { flex-direction: column; align-items: flex-start; }
    .winner-big { align-items: flex-start; }
    th, td { padding: 9px 11px; }
    .bar-track { width: 60px; }
  }
</style>''';

// ---------------------------------------------------------------------------
// Inline JS — progress shell (SSE → live status + reload on done)
// ---------------------------------------------------------------------------

const String _progressScript = r'''<script>
(function () {
  var TOKEN = "__TOKEN__";
  function u(path) { return path + (path.indexOf('?') >= 0 ? '&' : '?') + 't=' + encodeURIComponent(TOKEN); }

  // Elapsed timer.
  var start = Date.now();
  var el = document.getElementById('elapsed');
  setInterval(function () {
    var s = Math.floor((Date.now() - start) / 1000);
    var m = Math.floor(s / 60);
    el.textContent = m + ':' + String(s % 60).padStart(2, '0');
  }, 1000);

  function applyState(id, state, status) {
    var li = document.querySelector('.run-item[data-cand="' + (window.CSS && CSS.escape ? CSS.escape(id) : id) + '"]');
    if (!li) return;
    li.setAttribute('data-state', state);
    var st = li.querySelector('.run-status');
    if (st) st.textContent = status;
  }
  function outcomeState(o) {
    if (o === 'ok') return ['ok', 'ok'];
    if (o === 'skipped') return ['skip', 'übersprungen'];
    return ['fail', o];
  }

  var es = new EventSource(u('/events'));
  es.onmessage = function (ev) {
    var msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.type === 'snapshot') {
      (msg.states || []).forEach(function (s) {
        if (s.state === 'running') applyState(s.id, 'running', 'läuft…');
        else if (s.state === 'pending') applyState(s.id, 'pending', 'wartet');
        else { var os = outcomeState(s.outcome); applyState(s.id, os[0], os[1]); }
      });
      if (msg.finished) location.reload();
    } else if (msg.type === 'start') {
      applyState(msg.id, 'running', 'läuft…');
    } else if (msg.type === 'finish') {
      var os = outcomeState(msg.outcome);
      applyState(msg.id, os[0], os[1]);
    } else if (msg.type === 'done') {
      es.close();
      setTimeout(function () { location.reload(); }, 350);
    }
  };
  es.onerror = function () { /* keep retrying; server may still be starting */ };
})();
</script>''';

// ---------------------------------------------------------------------------
// Inline JS — live microphone test (record → WAV 16 kHz mono → /api/transcribe)
// ---------------------------------------------------------------------------

const String _liveScript = r'''<script>
(function () {
  var TOKEN = "__TOKEN__";
  function u(path) { return path + (path.indexOf('?') >= 0 ? '&' : '?') + 't=' + encodeURIComponent(TOKEN); }
  function $(id) { return document.getElementById(id); }

  var panel = $('live-panel'), candEl = $('live-cand'), recBtn = $('rec-btn'),
      stateEl = $('rec-state'), result = $('live-result');
  var currentCand = null, recorder = null, stream = null, chunks = [],
      recording = false, stopAt = 0;

  document.querySelectorAll('.live-btn').forEach(function (b) {
    b.addEventListener('click', function () {
      currentCand = b.dataset.cand;
      candEl.textContent = b.dataset.label || b.dataset.cand;
      panel.hidden = false;
      result.hidden = true;
      recBtn.disabled = false;
      stateEl.textContent = 'bereit — Aufnahme starten';
      panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  });

  recBtn.addEventListener('click', function () {
    if (!recording) startRec(); else stopRec();
  });

  function setBusy(txt) {
    recBtn.classList.remove('recording'); recBtn.classList.add('busy');
    recBtn.disabled = true; stateEl.textContent = txt;
  }

  async function startRec() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      stateEl.textContent = 'Mikrofon wird von diesem Browser nicht unterstützt.';
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
    } catch (e) {
      stateEl.textContent = 'Kein Mikrofon-Zugriff: ' + (e && e.message ? e.message : e);
      return;
    }
    chunks = [];
    recorder = new MediaRecorder(stream);
    recorder.ondataavailable = function (e) { if (e.data.size) chunks.push(e.data); };
    recorder.onstop = onStop;
    recorder.start();
    recording = true;
    recBtn.classList.add('recording');
    recBtn.textContent = '■ Aufnahme stoppen';
    stateEl.textContent = 'Aufnahme läuft — sprich jetzt …';
  }

  function stopRec() {
    if (!recorder) return;
    stopAt = performance.now();
    recording = false;
    recBtn.textContent = '● Aufnahme starten';
    setBusy('verarbeite Aufnahme …');
    recorder.stop();
    if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
  }

  async function onStop() {
    try {
      var blob = new Blob(chunks, { type: chunks[0] ? chunks[0].type : 'audio/webm' });
      var buf = await blob.arrayBuffer();
      var AC = window.AudioContext || window.webkitAudioContext;
      var ac = new AC();
      var decoded = await ac.decodeAudioData(buf);
      ac.close();
      var wav = encodeWav16k(decoded);
      var audioMs = Math.round(decoded.duration * 1000);
      setBusy('transkribiere mit ' + currentCand + ' …');
      var t0 = performance.now();
      var resp = await fetch(u('/api/transcribe?candidate=' + encodeURIComponent(currentCand)), {
        method: 'POST',
        headers: { 'Content-Type': 'audio/wav' },
        body: wav
      });
      var totalMs = Math.round(performance.now() - stopAt);
      if (!resp.ok) throw new Error('Server-Fehler ' + resp.status);
      var data = await resp.json();
      showResult(data, audioMs, totalMs);
    } catch (e) {
      stateEl.textContent = 'Fehler: ' + (e && e.message ? e.message : e);
      recBtn.classList.remove('busy'); recBtn.disabled = false;
    }
  }

  function fmtMs(ms) {
    if (ms == null) return '—';
    return ms < 1000 ? ms + ' ms' : (ms / 1000).toFixed(1).replace('.', ',') + ' s';
  }
  function showResult(data, audioMs, totalMs) {
    recBtn.classList.remove('busy'); recBtn.disabled = false;
    stateEl.textContent = data.outcome === 'ok' ? 'fertig' : ('Ergebnis: ' + data.outcome);
    result.hidden = false;
    $('m-total').textContent = fmtMs(totalMs);
    $('m-engine').textContent = fmtMs(data.durationMs);
    $('m-audio').textContent = fmtMs(audioMs);
    var rtf = (data.durationMs && audioMs) ? (data.durationMs / audioMs) : null;
    $('m-rtf').textContent = rtf != null ? rtf.toFixed(2) : '—';
    $('m-text').textContent = data.transcribedText || data.errorDetail || '(kein Text)';
  }

  // Downmix to mono, resample to 16 kHz, encode 16-bit PCM WAV.
  function encodeWav16k(buffer) {
    var outRate = 16000, inRate = buffer.sampleRate, ch = buffer.numberOfChannels;
    var inLen = buffer.length;
    var mono = new Float32Array(inLen);
    for (var c = 0; c < ch; c++) {
      var d = buffer.getChannelData(c);
      for (var i = 0; i < inLen; i++) mono[i] += d[i] / ch;
    }
    var ratio = inRate / outRate;
    var outLen = Math.floor(inLen / ratio);
    var out = new Int16Array(outLen);
    for (var j = 0; j < outLen; j++) {
      var pos = j * ratio, i0 = Math.floor(pos), i1 = Math.min(i0 + 1, inLen - 1);
      var s = mono[i0] + (mono[i1] - mono[i0]) * (pos - i0);
      s = Math.max(-1, Math.min(1, s));
      out[j] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }
    var bytes = outLen * 2, ab = new ArrayBuffer(44 + bytes), dv = new DataView(ab);
    function ws(off, str) { for (var k = 0; k < str.length; k++) dv.setUint8(off + k, str.charCodeAt(k)); }
    ws(0, 'RIFF'); dv.setUint32(4, 36 + bytes, true); ws(8, 'WAVE');
    ws(12, 'fmt '); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true);
    dv.setUint16(22, 1, true); dv.setUint32(24, outRate, true);
    dv.setUint32(28, outRate * 2, true); dv.setUint16(32, 2, true);
    dv.setUint16(34, 16, true); ws(36, 'data'); dv.setUint32(40, bytes, true);
    var off = 44;
    for (var n = 0; n < outLen; n++) { dv.setInt16(off, out[n], true); off += 2; }
    return ab;
  }

  // Quit button → shut the local server down.
  var quit = $('quit-btn');
  if (quit) quit.addEventListener('click', async function () {
    quit.textContent = 'beende …'; quit.disabled = true;
    try { await fetch(u('/api/shutdown'), { method: 'POST' }); } catch (e) {}
    document.body.innerHTML = '<main class="container"><section class="run-hero">' +
      '<h1 class="run-title">Tool beendet</h1>' +
      '<p class="run-sub">Du kannst dieses Fenster jetzt schließen.</p></section></main>';
  });
})();
</script>''';
