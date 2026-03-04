/* ── Analytics Page ──────────────────────────────────── */
let _analyticsPeriod = 30;

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

  // Summary cards
  html += `<div class="analytics-summary">
    <div class="stat-card"><div class="stat-value">${data.totalEntries}</div><div class="stat-label">${t('analytics.total')}</div></div>
    <div class="stat-card"><div class="stat-value accent">${fmtDur(avgDur)}</div><div class="stat-label">${t('analytics.avg_duration')}</div></div>
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

  const days = Object.keys(dailyCounts).sort();
  const maxCount = Math.max(...Object.values(dailyCounts), 1);
  const w = 100; // percentage width
  const h = 140;
  const padding = { top: 10, bottom: 25, left: 5, right: 5 };
  const chartH = h - padding.top - padding.bottom;

  // Show last N days with gaps filled
  const last14 = [];
  const end = new Date(days[days.length - 1]);
  const numDays = Math.min(days.length, 14);
  for (let i = numDays - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    last14.push({ date: key, count: dailyCounts[key] || 0, label: d.getDate().toString() });
  }

  const barW = (100 - 10) / last14.length;
  let bars = '';
  last14.forEach((d, i) => {
    const barH = (d.count / maxCount) * chartH;
    const x = 5 + i * barW + barW * 0.15;
    const bw = barW * 0.7;
    bars += `<rect class="bar" x="${x}%" y="${padding.top + chartH - barH}" width="${bw}%" height="${barH}"/>`;
    if (last14.length <= 14) {
      bars += `<text x="${x + bw / 2}%" y="${h - 4}" text-anchor="middle">${d.label}</text>`;
    }
  });

  return `<svg class="bar-chart" viewBox="0 0 400 ${h}" preserveAspectRatio="none">
    <line class="axis" x1="0" y1="${padding.top + chartH}" x2="400" y2="${padding.top + chartH}"/>
    ${bars.replace(/%/g, '%')}
  </svg>`;
}

function renderModelDonut(modelCounts) {
  if (!modelCounts || Object.keys(modelCounts).length === 0) {
    return `<p style="color:var(--text-hint);font-size:12px">${t('analytics.no_data')}</p>`;
  }

  const colors = ['#22D3EE', '#67E8F9', '#06B6D4', '#0891B2', '#0E7490', '#155E75'];
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
    return `<div style="flex:1;text-align:center">
      <div style="display:flex;align-items:flex-end;height:100px;justify-content:center">
        <div class="dur-bar" style="height:${Math.max(pct, 2)}%;width:80%"></div>
      </div>
      <div class="dur-bar-label">${k}</div>
      <div style="font-size:10px;color:var(--text-hint);text-align:center">${v}</div>
    </div>`;
  }).join('')}</div>`;
}
