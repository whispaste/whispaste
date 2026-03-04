/* ── Analytics Page ──────────────────────────────────── */
let _analyticsPeriod = 30;
let _analyticsInterval = null;

function startAnalyticsAutoRefresh() {
  stopAnalyticsAutoRefresh();
  _analyticsInterval = setInterval(() => loadAnalytics(), 3000);
}
function stopAnalyticsAutoRefresh() {
  if (_analyticsInterval) { clearInterval(_analyticsInterval); _analyticsInterval = null; }
}

async function loadAnalytics(periodDays) {
  if (periodDays !== undefined) _analyticsPeriod = periodDays;
  const container = document.getElementById('analytics-content');
  if (!container) return;

  // Update period buttons
  document.querySelectorAll('.period-btn').forEach(btn => {
    btn.classList.toggle('active', parseInt(btn.dataset.period) === _analyticsPeriod);
  });

  let data;
  try {
    const raw = await window.getAnalytics(_analyticsPeriod);
    data = typeof raw === 'string' ? JSON.parse(raw) : raw;
  } catch (e) {
    container.innerHTML = `<div class="analytics-empty"><p>${t('analytics.error')}</p></div>`;
    return;
  }

  if (!data || data.totalEntries === 0) {
    container.innerHTML = `<div class="analytics-empty">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/></svg>
      <p>${t('analytics.empty')}</p>
    </div>`;
    return;
  }

  const avgDur = data.avgDuration || 0;
  const minDur = data.minDuration || 0;
  const maxDur = data.maxDuration || 0;
  const avgProc = data.avgProcessingDuration || 0;
  const fmtCost = v => '$' + (v || 0).toFixed(4);
  const fmtDur = s => s < 60 ? Math.round(s) + 's' : (s / 60).toFixed(1) + 'm';

  let html = '';

  // Savings banner
  if (data.savings > 0) {
    html += `<div class="savings-banner">
      <svg class="savings-icon icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 5c-1.5 0-2.8 1.4-3 2-3.5-1.5-11-.3-11 5 0 1.8 0 3 2 4.5V20h4v-2h3v2h4v-4c1-1 3-3.5 3-6 0-2-1-3-2-3"/><path d="M2 9.1C1.2 10 1 11 1 12c0 1.5.5 2.8 1 3.5"/></svg>
      <span class="savings-text">${t('analytics.savings_prefix')} <span class="savings-amount">${fmtCost(data.savings)}</span> ${t('analytics.savings_suffix')}</span>
    </div>`;
  }

  // Summary cards — avg with min/max range
  const durationDetail = data.totalEntries > 0 ? `<div class="stat-range">${fmtDur(minDur)} – ${fmtDur(maxDur)}</div>` : '';
  const processingDetail = avgProc > 0 ? `<div class="stat-range">${fmtDur(data.totalProcessingTime || 0)} ${t('analytics.processing_total')}</div>` : '';
  html += `<div class="analytics-summary">
    <div class="stat-card"><div class="stat-value">${data.totalEntries}</div><div class="stat-label">${t('analytics.total')}</div></div>
    <div class="stat-card"><div class="stat-value accent">${fmtDur(avgDur)}</div><div class="stat-label">${t('analytics.avg_duration')}</div>${durationDetail}</div>
    <div class="stat-card"><div class="stat-value">${avgProc > 0 ? fmtDur(avgProc) : '—'}</div><div class="stat-label">${t('analytics.avg_processing')}</div>${processingDetail}</div>
    <div class="stat-card"><div class="stat-value">${data.localEntries || 0}</div><div class="stat-label">${t('analytics.local')}</div></div>
    <div class="stat-card"><div class="stat-value">${fmtCost(data.totalCost)}</div><div class="stat-label">${t('analytics.cost')}</div></div>
  </div>`;

  // Charts
  html += '<div class="analytics-charts">';

  // Daily bar chart
  html += `<div class="chart-card full-width">
    <div class="chart-title">${t('analytics.daily_chart')}</div>
    <div class="chart-container">${renderDailyChart(data.dailyCounts)}</div>
  </div>`;

  // Model donut chart
  html += `<div class="chart-card">
    <div class="chart-title">${t('analytics.model_chart')}</div>
    <div class="chart-container">${renderModelDonut(data.modelCounts)}</div>
  </div>`;

  // Duration histogram
  html += `<div class="chart-card">
    <div class="chart-title">${t('analytics.duration_chart')}</div>
    <div class="chart-container">${renderDurationBars(data.durationBuckets)}</div>
  </div>`;

  html += '</div>';
  container.innerHTML = html;
}

function renderDailyChart(dailyCounts) {
  if (!dailyCounts || Object.keys(dailyCounts).length === 0) {
    return `<p style="color:var(--text-hint);font-size:12px">${t('analytics.no_data')}</p>`;
  }

  // Fill ALL days in the selected period
  const allDays = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dataDays = Object.keys(dailyCounts).sort();

  if (_analyticsPeriod > 0) {
    // Fixed range: show exactly N days
    for (let i = _analyticsPeriod - 1; i >= 0; i--) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      const key = d.toISOString().slice(0, 10);
      allDays.push({ date: key, count: dailyCounts[key] || 0, label: d.getDate().toString() });
    }
  } else {
    // All Time: span from earliest data to today
    const earliest = new Date(dataDays[0]);
    earliest.setHours(0, 0, 0, 0);
    const span = Math.round((today - earliest) / 86400000) + 1;
    for (let i = span - 1; i >= 0; i--) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      const key = d.toISOString().slice(0, 10);
      allDays.push({ date: key, count: dailyCounts[key] || 0, label: d.getDate().toString() });
    }
  }

  const maxCount = Math.max(...allDays.map(d => d.count), 1);
  const h = 140;
  const padding = { top: 10, bottom: 25, left: 30, right: 5 };
  const chartH = h - padding.top - padding.bottom;
  const chartW = 400 - padding.left - padding.right;

  // Grid lines (3-4 horizontal lines with value labels)
  const gridSteps = 4;
  let gridLines = '';
  for (let i = 0; i <= gridSteps; i++) {
    const y = padding.top + chartH - (i / gridSteps) * chartH;
    const val = Math.round((i / gridSteps) * maxCount);
    gridLines += `<line class="grid-line" x1="${padding.left}" y1="${y}" x2="${400 - padding.right}" y2="${y}"/>`;
    gridLines += `<text class="grid-label" x="${padding.left - 4}" y="${y + 3}" text-anchor="end">${val}</text>`;
  }

  const barW = chartW / allDays.length;
  const maxBarPx = 48;
  let bars = '';
  // Show labels selectively to avoid overlap
  const labelEvery = allDays.length > 14 ? Math.ceil(allDays.length / 14) : 1;
  allDays.forEach((d, i) => {
    const barH = (d.count / maxCount) * chartH;
    const bwRaw = barW * 0.7;
    const bw = Math.min(bwRaw, maxBarPx);
    const x = padding.left + i * barW + (barW - bw) / 2;
    if (d.count > 0) {
      bars += `<rect class="bar" x="${x}" y="${padding.top + chartH - barH}" width="${bw}" height="${barH}" rx="2"/>`;
    }
    if (i % labelEvery === 0) {
      bars += `<text x="${padding.left + i * barW + barW / 2}" y="${h - 4}" text-anchor="middle">${d.label}</text>`;
    }
  });

  return `<svg class="bar-chart" viewBox="0 0 400 ${h}" preserveAspectRatio="xMidYMid meet">
    ${gridLines}
    <line class="axis" x1="${padding.left}" y1="${padding.top + chartH}" x2="${400 - padding.right}" y2="${padding.top + chartH}"/>
    ${bars}
  </svg>`;
}

function renderModelDonut(modelCounts) {
  if (!modelCounts || Object.keys(modelCounts).length === 0) {
    return `<p style="color:var(--text-hint);font-size:12px">${t('analytics.no_data')}</p>`;
  }

  const colors = ['#22D3EE', '#F59E0B', '#8B5CF6', '#EF4444', '#22C55E', '#EC4899'];
  const entries = Object.entries(modelCounts).sort((a, b) => b[1] - a[1]);
  const total = entries.reduce((s, e) => s + e[1], 0);

  const cx = 90, cy = 90, r = 70, innerR = 45;
  let paths = '';
  const legend = [];

  // Single model: render full circle instead of degenerate arc
  if (entries.length === 1) {
    const [model, count] = entries[0];
    const color = colors[0];
    paths = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${color}"/>
             <circle cx="${cx}" cy="${cy}" r="${innerR}" fill="var(--bg-card)"/>`;
    legend.push(`<span class="donut-legend-item"><span class="donut-legend-dot" style="background:${color}"></span>${model} (${count})</span>`);
  } else {
    let startAngle = -Math.PI / 2;
    entries.forEach(([model, count], i) => {
      const angle = (count / total) * Math.PI * 2;
      const endAngle = startAngle + angle;
      const largeArc = angle > Math.PI ? 1 : 0;
      const x1 = cx + r * Math.cos(startAngle), y1 = cy + r * Math.sin(startAngle);
      const x2 = cx + r * Math.cos(endAngle), y2 = cy + r * Math.sin(endAngle);
      const ix1 = cx + innerR * Math.cos(endAngle), iy1 = cy + innerR * Math.sin(endAngle);
      const ix2 = cx + innerR * Math.cos(startAngle), iy2 = cy + innerR * Math.sin(startAngle);
      const color = colors[i % colors.length];
      paths += `<path d="M${x1},${y1} A${r},${r} 0 ${largeArc} 1 ${x2},${y2} L${ix1},${iy1} A${innerR},${innerR} 0 ${largeArc} 0 ${ix2},${iy2} Z" fill="${color}"/>`;
      legend.push(`<span class="donut-legend-item"><span class="donut-legend-dot" style="background:${color}"></span>${model} (${count})</span>`);
      startAngle = endAngle;
    });
  }

  return `<svg class="donut-chart" viewBox="0 0 180 180">${paths}</svg>
    <div class="donut-legend">${legend.join('')}</div>`;
}

function renderDurationBars(buckets) {
  if (!buckets) return '';
  const keys = ['<15s', '15-30s', '30-60s', '1-3m', '>3m'];
  const maxVal = Math.max(...keys.map(k => buckets[k] || 0), 1);

  return `<div class="duration-bars">${keys.map(k => {
    const v = buckets[k] || 0;
    const pct = (v / maxVal) * 100;
    return `<div class="dur-col">
      <div class="dur-bar-wrap">
        <div class="dur-bar" style="height:${Math.max(pct, 2)}%"></div>
      </div>
      <div class="dur-bar-label">${k}</div>
      <div class="dur-bar-value">${v}</div>
    </div>`;
  }).join('')}</div>`;
}
