/// HTML report renderer for WhisPaste GPU-Probe results.
///
/// Produces a self-contained `<!DOCTYPE html>` document with all CSS inlined.
/// No external resources, no CDN references, no JS frameworks.
library;

import 'probe_types.dart';
import 'ranking.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Renders [report] as a self-contained HTML document (German UI, UTF-8).
///
/// The document includes:
/// - Winner banner (best non-baseline `ok` candidate) or fallback message.
/// - Ranking table for all `ok` candidates with speedup factors.
/// - Failed / not-runnable section for non-`ok` candidates.
/// - Hardware context section when [ProbeReport.hardwareContext] is present.
/// - Warning banner when the CPU baseline is missing.
String formatProbeReportHtml(ProbeReport report) {
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
  _writeHeader(b, report);
  b.writeln('<main class="container">');
  _writeBaselineMissingWarning(b, ranking);
  _writeWinnerBanner(b, ranking, winner);
  _writeRankingTable(b, ranking, winner);
  _writeFailedSection(b, ranking);
  _writeHardwareSection(b, report);
  b.writeln('</main>');
  _writeFooter(b, report);
  b.writeln('</body>');
  b.write('</html>');

  return b.toString();
}

// ---------------------------------------------------------------------------
// Section helpers
// ---------------------------------------------------------------------------

void _writeHeader(StringBuffer b, ProbeReport report) {
  b.writeln('<header class="site-header">');
  b.writeln('  <span class="header-title">WhisPaste GPU-Probe Report</span>');
  b.writeln(
    '  <span class="header-meta">v${_esc(report.version)}'
    ' &nbsp;·&nbsp; ${_esc(report.timestamp.toIso8601String())}</span>',
  );
  b.writeln('</header>');
}

void _writeBaselineMissingWarning(StringBuffer b, RankingResult ranking) {
  if (!ranking.cpuBaselineMissing) return;
  b.writeln('<div class="banner banner-warn">');
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
    b.writeln('<div class="banner banner-info">');
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
  final latStr = latMs != null ? '$latMs ms' : '—';
  final label = _candidateLabel(winner.result);

  b.writeln('<div class="banner banner-winner">');
  b.writeln('  <div class="winner-crown">🏆 Beste lauffähige GPU-Option</div>');
  b.writeln('  <div class="winner-name">${_esc(label)}</div>');
  b.writeln('  <div class="winner-stats">');
  b.writeln(
    '    <span class="stat"><span class="stat-label">Speedup</span>'
    '<span class="stat-value">${_esc(speedupStr)} schneller als CPU</span></span>',
  );
  b.writeln(
    '    <span class="stat"><span class="stat-label">WER</span>'
    '<span class="stat-value">${_esc(werStr)}</span></span>',
  );
  b.writeln(
    '    <span class="stat"><span class="stat-label">Latenz</span>'
    '<span class="stat-value">${_esc(latStr)}</span></span>',
  );
  b.writeln('  </div>');
  b.writeln('</div>');
}

void _writeRankingTable(
  StringBuffer b,
  RankingResult ranking,
  RankedCandidate? winner,
) {
  if (ranking.ranked.isEmpty) return;
  b.writeln('<section>');
  b.writeln('<h2>Geschwindigkeits-Ranking</h2>');
  b.writeln('<table>');
  b.writeln('<thead><tr>');
  b.writeln('  <th>Rang</th>');
  b.writeln('  <th>Kandidat</th>');
  b.writeln('  <th>Ergebnis</th>');
  b.writeln('  <th>Latenz</th>');
  b.writeln('  <th>Realtime-Faktor</th>');
  b.writeln('  <th>× vs. CPU</th>');
  b.writeln('  <th>WER</th>');
  b.writeln('</tr></thead>');
  b.writeln('<tbody>');
  for (var i = 0; i < ranking.ranked.length; i++) {
    _writeRankingRow(b, ranking.ranked[i], i + 1, winner);
  }
  b.writeln('</tbody>');
  b.writeln('</table>');
  b.writeln('</section>');
}

void _writeRankingRow(
  StringBuffer b,
  RankedCandidate rc,
  int rank,
  RankedCandidate? winner,
) {
  final isWinner =
      winner != null && rc.result.candidateId == winner.result.candidateId;
  final rowClass = StringBuffer('');
  if (rc.isCpuBaseline) rowClass.write(' row-baseline');
  if (isWinner) rowClass.write(' row-winner');

  final durStr = rc.result.durationMs != null
      ? '${rc.result.durationMs} ms'
      : '—';
  final rtfStr = rc.result.realtimeFactor != null
      ? rc.result.realtimeFactor!.toStringAsFixed(2)
      : '—';
  final speedStr = _formatSpeedupDe(rc.speedupFactor);
  final werStr = _formatWerDe(rc.result.wer);
  final label = rc.isCpuBaseline
      ? '${_candidateLabel(rc.result)} <span class="badge-baseline">Baseline</span>'
      : _esc(_candidateLabel(rc.result));

  b.writeln('<tr class="${rowClass.toString().trim()}">');
  b.writeln('  <td class="rank">$rank</td>');
  b.writeln('  <td class="candidate-name">$label</td>');
  b.writeln('  <td><span class="badge outcome-ok">ok</span></td>');
  b.writeln('  <td>${_esc(durStr)}</td>');
  b.writeln('  <td>${_esc(rtfStr)}</td>');
  b.writeln('  <td class="speedup">${_esc(speedStr)}</td>');
  b.writeln('  <td>${_esc(werStr)}</td>');
  b.writeln('</tr>');
}

void _writeFailedSection(StringBuffer b, RankingResult ranking) {
  if (ranking.failed.isEmpty) return;
  b.writeln('<section>');
  b.writeln('<h2>Nicht lauffähige Kandidaten</h2>');
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
  b.writeln('  <td class="error-detail">${_esc(detail)}</td>');
  b.writeln('</tr>');
}

void _writeHardwareSection(StringBuffer b, ProbeReport report) {
  if (report.hardwareContext == null) return;
  final hw = report.hardwareContext!;
  b.writeln('<section>');
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

void _writeFooter(StringBuffer b, ProbeReport report) {
  b.writeln('<footer class="site-footer">');
  b.writeln(
    '  WhisPaste GPU-Probe v${_esc(report.version)} &nbsp;·&nbsp; '
    '${_esc(report.timestamp.toIso8601String())}',
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
// Inline CSS
// ---------------------------------------------------------------------------

const String _css = '''
<style>
  :root {
    --accent: #4f6ef7;
    --accent-dark: #3451d1;
    --green: #16a34a;
    --red: #dc2626;
    --amber: #d97706;
    --grey: #6b7280;
    --win-bg: #ecfdf5;
    --win-border: #16a34a;
    --info-bg: #eff6ff;
    --info-border: #3b82f6;
    --warn-bg: #fffbeb;
    --warn-border: #d97706;
    --header-bg: #1e293b;
    --header-fg: #f1f5f9;
    --row-hover: #f8fafc;
    --row-baseline: #eff6ff;
    --row-winner: #f0fdf4;
    --border: #e2e8f0;
    --text: #0f172a;
    --muted: #64748b;
    --font: system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    --mono: ui-monospace, "Cascadia Code", "Fira Code", monospace;
  }

  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: var(--font);
    font-size: 14px;
    color: var(--text);
    background: #f8fafc;
    line-height: 1.6;
  }

  /* ── Header ────────────────────────────────────────────────────────────── */
  .site-header {
    background: var(--header-bg);
    color: var(--header-fg);
    padding: 14px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    flex-wrap: wrap;
  }
  .header-title {
    font-size: 16px;
    font-weight: 700;
    letter-spacing: 0.01em;
  }
  .header-meta {
    font-size: 12px;
    color: #94a3b8;
    font-family: var(--mono);
  }

  /* ── Main container ─────────────────────────────────────────────────────── */
  .container {
    max-width: 1100px;
    margin: 28px auto;
    padding: 0 20px;
    display: flex;
    flex-direction: column;
    gap: 28px;
  }

  /* ── Banners ────────────────────────────────────────────────────────────── */
  .banner {
    border-radius: 10px;
    padding: 20px 24px;
    border-left: 5px solid;
  }
  .banner-winner {
    background: var(--win-bg);
    border-color: var(--win-border);
  }
  .banner-info {
    background: var(--info-bg);
    border-color: var(--info-border);
    color: #1e40af;
    font-weight: 500;
  }
  .banner-warn {
    background: var(--warn-bg);
    border-color: var(--warn-border);
    color: #92400e;
  }
  .banner-warn code {
    background: rgba(0,0,0,0.07);
    padding: 1px 5px;
    border-radius: 4px;
    font-family: var(--mono);
    font-size: 12px;
  }
  .winner-crown {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--green);
    font-weight: 700;
    margin-bottom: 6px;
  }
  .winner-name {
    font-size: 22px;
    font-weight: 700;
    font-family: var(--mono);
    color: #064e3b;
    margin-bottom: 12px;
  }
  .winner-stats {
    display: flex;
    flex-wrap: wrap;
    gap: 20px;
  }
  .stat {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .stat-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    font-weight: 600;
  }
  .stat-value {
    font-size: 16px;
    font-weight: 700;
    color: #064e3b;
  }

  /* ── Sections ───────────────────────────────────────────────────────────── */
  section h2 {
    font-size: 15px;
    font-weight: 700;
    color: #1e293b;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin-bottom: 14px;
    padding-bottom: 8px;
    border-bottom: 2px solid var(--border);
  }

  /* ── Tables ─────────────────────────────────────────────────────────────── */
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
    background: #fff;
    border-radius: 8px;
    overflow: hidden;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  }
  thead tr {
    background: #f1f5f9;
  }
  th {
    text-align: left;
    padding: 10px 14px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    font-weight: 700;
    white-space: nowrap;
  }
  td {
    padding: 10px 14px;
    border-top: 1px solid var(--border);
    vertical-align: middle;
  }
  tbody tr:hover td {
    background: var(--row-hover);
  }
  .row-baseline td {
    background: var(--row-baseline);
  }
  .row-baseline:hover td {
    background: #dbeafe;
  }
  .row-winner td {
    background: var(--row-winner);
  }
  .row-winner:hover td {
    background: #dcfce7;
  }
  .rank {
    font-weight: 700;
    color: var(--muted);
    text-align: center;
    width: 50px;
  }
  .candidate-name {
    font-family: var(--mono);
    font-size: 12px;
    font-weight: 600;
  }
  .speedup {
    font-weight: 700;
    color: var(--accent-dark);
  }
  .error-detail {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--muted);
    max-width: 500px;
    word-break: break-all;
  }

  /* ── Badges ─────────────────────────────────────────────────────────────── */
  .badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 9999px;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .outcome-ok {
    background: #dcfce7;
    color: #14532d;
  }
  .outcome-crashed {
    background: #fee2e2;
    color: #7f1d1d;
  }
  .outcome-hung {
    background: #fef3c7;
    color: #78350f;
  }
  .outcome-skipped {
    background: #f3f4f6;
    color: #374151;
  }
  .badge-baseline {
    display: inline-block;
    margin-left: 6px;
    padding: 1px 6px;
    border-radius: 4px;
    font-size: 10px;
    font-weight: 600;
    background: #dbeafe;
    color: #1e40af;
    vertical-align: middle;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  /* ── Hardware grid ──────────────────────────────────────────────────────── */
  .hw-grid {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 8px 20px;
    background: #fff;
    border-radius: 8px;
    padding: 16px 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
  }
  .hw-grid dt {
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    padding-top: 1px;
  }
  .hw-grid dd {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--text);
  }

  /* ── Footer ─────────────────────────────────────────────────────────────── */
  .site-footer {
    text-align: center;
    padding: 18px;
    font-size: 11px;
    color: var(--muted);
    border-top: 1px solid var(--border);
    margin-top: 16px;
  }

  @media (max-width: 680px) {
    .winner-stats { gap: 12px; }
    .winner-name { font-size: 16px; }
    table { font-size: 12px; }
    th, td { padding: 8px 10px; }
  }
</style>''';
