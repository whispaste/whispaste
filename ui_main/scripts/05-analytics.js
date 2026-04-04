/* ── Analytics Page ──────────────────────────────────── */
let _analyticsPeriod = 30;
let _analyticsData = null;
let _analyticsInterval = null;
let _analyticsResizeObserver = null;
let _modelColorMap = {};
let _benchmarkSort = { column: 'speed', ascending: false };

function infoTip(tipKey) {
  return `<span class="info-tip" title="${t(tipKey)}">
    <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" style="vertical-align:-2px;opacity:0.5;margin-left:4px">
      <circle cx="8" cy="8" r="7" fill="none" stroke="currentColor" stroke-width="1.5"/>
      <text x="8" y="12" text-anchor="middle" font-size="11" font-weight="bold">i</text>
    </svg>
  </span>`;
}

function startAnalyticsAutoRefresh() {
  stopAnalyticsAutoRefresh();
  _analyticsInterval = setInterval(() => loadAnalytics(), 2000);
  _initAnalyticsResize();
}
function stopAnalyticsAutoRefresh() {
  if (_analyticsInterval) { clearInterval(_analyticsInterval); _analyticsInterval = null; }
  if (_analyticsResizeObserver) { _analyticsResizeObserver.disconnect(); _analyticsResizeObserver = null; }
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
    container.innerHTML = `<div class="analytics-empty">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <div class="analytics-empty-title">${t('analytics.error_title') || t('analytics.error')}</div>
      <p class="analytics-empty-text">${t('analytics.error_text') || t('analytics.error')}</p>
    </div>`;
    return;
  }

  if (!data || data.totalEntries === 0) {
    container.innerHTML = `<div class="analytics-empty">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/></svg>
      <div class="analytics-empty-title">${t('analytics.empty_title') || t('analytics.empty')}</div>
      <p class="analytics-empty-text">${t('analytics.empty_text') || t('analytics.empty')}</p>
    </div>`;
    return;
  }

  const avgDur = data.avgDuration || 0;
  const minDur = data.minDuration || 0;
  const maxDur = data.maxDuration || 0;
  const avgProc = data.avgProcessingDuration || 0;
  const fmtCost = v => '$' + (v || 0).toFixed(4);
  const fmtDur = s => s < 60 ? Math.round(s) + 's' : (s / 60).toFixed(1) + 'm';
  const fmtTimeSaved = min => {
    if (min < 1) return '<1 min';
    if (min < 60) return Math.round(min) + ' min';
    const h = Math.floor(min / 60);
    const m = Math.round(min % 60);
    return m > 0 ? `${h} h ${m} min` : `${h} h`;
  };

  let html = '';

  // Savings banner
  if (data.savings > 0) {
    html += `<div class="savings-banner">
      <svg class="savings-icon icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 5c-1.5 0-2.8 1.4-3 2-3.5-1.5-11-.3-11 5 0 1.8 0 3 2 4.5V20h4v-2h3v2h4v-4c1-1 3-3.5 3-6 0-2-1-3-2-3"/><path d="M2 9.1C1.2 10 1 11 1 12c0 1.5.5 2.8 1 3.5"/></svg>
      <span class="savings-text">${t('analytics.savings_prefix')} <span class="savings-amount">${fmtCost(data.savings)}</span> ${t('analytics.savings_suffix')}</span>
    </div>`;
  }

  // Summary cards
  const durationDetail = data.totalEntries > 0 ? `<div class="stat-range">${fmtDur(minDur)} – ${fmtDur(maxDur)}</div>` : '';
  const processingDetail = avgProc > 0 ? `<div class="stat-range">${fmtDur(data.totalProcessingTime || 0)} ${t('analytics.processing_total')}</div>` : '';
  const timeSaved = data.timeSaved || 0;
  const timeSavedHint = timeSaved > 0 ? `<div class="stat-range">${t('analytics.time_saved_hint')}</div>` : '';
  const avgSpeed = data.avgSpeedRatio || 0;
  const avgSpeedStr = avgSpeed > 0 ? `${avgSpeed.toFixed(1)}×` : '—';

  html += `<div class="analytics-summary">
    <div class="stat-card"><div class="stat-value">${data.totalEntries}</div><div class="stat-label">${t('analytics.total')}${infoTip('analytics.tip.total_entries')}</div></div>
    <div class="stat-card"><div class="stat-value">${Math.round(data.totalWords || 0).toLocaleString()}</div><div class="stat-label">${t('analytics.total_words')}${infoTip('analytics.tip.total_words')}</div></div>
    <div class="stat-card"><div class="stat-value">${Math.round(data.avgWordsPerEntry || 0)}</div><div class="stat-label">${t('analytics.avg_words')}</div></div>
    <div class="stat-card"><div class="stat-value green">${timeSaved > 0 ? fmtTimeSaved(timeSaved) : '—'}</div><div class="stat-label">${t('analytics.time_saved')}${infoTip('analytics.tip.time_saved')}</div>${timeSavedHint}</div>
    <div class="stat-card"><div class="stat-value accent">${fmtDur(avgDur)}</div><div class="stat-label">${t('analytics.avg_duration')}${infoTip('analytics.tip.total_duration')}</div>${durationDetail}</div>
    <div class="stat-card"><div class="stat-value">${avgProc > 0 ? fmtDur(avgProc) : '—'}</div><div class="stat-label">${t('analytics.avg_processing')}</div>${processingDetail}</div>
    <div class="stat-card"><div class="stat-value accent">${avgSpeedStr}</div><div class="stat-label">${t('analytics.avg_speed')}${infoTip('analytics.tip.avg_speed')}</div></div>
    <div class="stat-card"><div class="stat-value">${fmtCost(data.totalCost)}</div><div class="stat-label">${t('analytics.cost')}</div></div>
  </div>`;

  // Local vs Cloud ratio bar
  const localCount = data.localEntries || 0;
  const cloudCount = data.apiEntries || 0;
  const totalLc = localCount + cloudCount;
  if (totalLc > 0) {
    const localPct = Math.round((localCount / totalLc) * 100);
    const cloudPct = 100 - localPct;
    html += `<div class="local-cloud-bar">
      <div class="local-cloud-header">
        <span class="local-cloud-title">${t('analytics.local_cloud')}${infoTip('analytics.tip.local_cloud')}</span>
        <span class="local-cloud-counts">${localCount} ${t('analytics.local_label')} · ${cloudCount} ${t('analytics.cloud_label')}</span>
      </div>
      <div class="local-cloud-track">
        <div class="local-cloud-fill local-fill" style="width:${localPct}%" title="${t('analytics.local_label')} ${localPct}%"></div>
        <div class="local-cloud-fill cloud-fill" style="width:${cloudPct}%" title="${t('analytics.cloud_label')} ${cloudPct}%"></div>
      </div>
      <div class="local-cloud-labels">
        <span>${t('analytics.local_label')} ${localPct}%</span>
        <span>${t('analytics.cloud_label')} ${cloudPct}%</span>
      </div>
    </div>`;
  }

  // Charts
  html += '<div class="analytics-charts">';

  // Daily bar chart
  html += `<div class="chart-card full-width">
    <div class="chart-title">${t('analytics.daily_chart')}${infoTip('analytics.tip.daily_activity')}</div>
    <div class="chart-container">${renderDailyChart(data.dailyCounts, data.dailyModelCounts)}</div>
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

  // Model benchmarks table
  if (data.modelBenchmarks && Object.keys(data.modelBenchmarks).length > 0) {
    html += `<div class="chart-card full-width">
      <div class="chart-title">${t('analytics.benchmark_title')}${infoTip('analytics.tip.model_perf')}</div>
      <div class="chart-container">${renderBenchmarkTable(data.modelBenchmarks)}</div>
    </div>`;
  }

  // Monthly costs
  if (data.monthlyCosts && Object.keys(data.monthlyCosts).length > 0) {
    html += `<div class="chart-card">
      <div class="chart-title">${t('analytics.monthly_costs_title')}</div>
      <div class="chart-container">${renderMonthlyCosts(data.monthlyCosts)}</div>
    </div>`;
  }

  html += '</div>';

  // Reset button
  html += `<div class="analytics-reset-section">
    <button class="reset-stats-btn" onclick="confirmResetStatistics()">
      <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
      ${t('analytics.reset_btn')}
    </button>
  </div>`;
  _analyticsData = data;
  buildGlobalModelColorMap(data);
  container.innerHTML = html;
  _fitDailyChart(container, data.dailyCounts, data.dailyModelCounts);
}

function _localDateKey(d) {
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

function buildGlobalModelColorMap(data) {
  const localPalette = ['#22D3EE', '#10B981', '#F59E0B', '#F97316', '#06B6D4'];
  const apiPalette = ['#818CF8', '#A78BFA', '#8B5CF6', '#7C3AED', '#6D28D9'];
  _modelColorMap = {};

  const allModels = new Set();
  if (data.dailyModelCounts) {
    for (const entries of Object.values(data.dailyModelCounts)) {
      for (const m of entries) allModels.add(m.model + '|' + (m.isLocal ? '1' : '0'));
    }
  }
  if (data.modelCounts) {
    for (const model of Object.keys(data.modelCounts)) {
      const key1 = model + '|1', key0 = model + '|0';
      if (!allModels.has(key1) && !allModels.has(key0)) allModels.add(key0);
    }
  }
  if (data.modelBenchmarks) {
    for (const model of Object.keys(data.modelBenchmarks)) {
      const key1 = model + '|1', key0 = model + '|0';
      if (!allModels.has(key1) && !allModels.has(key0)) allModels.add(key0);
    }
  }

  let localIdx = 0, apiIdx = 0;
  for (const key of [...allModels].sort()) {
    const isLocal = key.endsWith('|1');
    const modelName = key.slice(0, key.lastIndexOf('|'));
    const color = isLocal
      ? localPalette[localIdx++ % localPalette.length]
      : apiPalette[apiIdx++ % apiPalette.length];
    _modelColorMap[key] = color;
    if (!_modelColorMap[modelName]) _modelColorMap[modelName] = color;
  }
}

function renderDailyChart(dailyCounts, dailyModelCounts, svgWidth) {
  if (!dailyCounts || Object.keys(dailyCounts).length === 0) {
    return `<p style="color:var(--text-hint);font-size:12px">${t('analytics.no_data')}</p>`;
  }

  const hasModelData = dailyModelCounts && Object.keys(dailyModelCounts).length > 0;

  const modelColorMap = _modelColorMap;

  // Fill ALL days in the selected period
  const allDays = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const dataDays = Object.keys(dailyCounts).sort();

  if (_analyticsPeriod > 0) {
    for (let i = _analyticsPeriod - 1; i >= 0; i--) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      const key = _localDateKey(d);
      allDays.push({ date: key, count: dailyCounts[key] || 0, label: d.getDate().toString() });
    }
  } else {
    const earliest = new Date(dataDays[0]);
    earliest.setHours(0, 0, 0, 0);
    const span = Math.round((today - earliest) / 86400000) + 1;
    for (let i = span - 1; i >= 0; i--) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      const key = _localDateKey(d);
      allDays.push({ date: key, count: dailyCounts[key] || 0, label: d.getDate().toString() });
    }
  }

  const maxCount = Math.max(...allDays.map(d => d.count), 1);
  const h = 140;
  const legendH = hasModelData ? 24 : 0;
  const totalH = h + legendH;
  const padding = { top: 10, bottom: 25, left: 30, right: 5 };
  const chartH = h - padding.top - padding.bottom;
  svgWidth = svgWidth || 400;
  const chartW = svgWidth - padding.left - padding.right;

  // Grid lines
  const gridSteps = 4;
  let gridLines = '';
  for (let i = 0; i <= gridSteps; i++) {
    const y = padding.top + chartH - (i / gridSteps) * chartH;
    const val = Math.round((i / gridSteps) * maxCount);
    gridLines += `<line class="grid-line" x1="${padding.left}" y1="${y}" x2="${svgWidth - padding.right}" y2="${y}"/>`;
    gridLines += `<text class="grid-label" x="${padding.left - 4}" y="${y + 3}" text-anchor="end">${val}</text>`;
  }

  const barW = chartW / allDays.length;
  const maxBarPx = 48;
  let bars = '';
  const minLabelSlot = 32;
  const maxLabels = Math.max(1, Math.floor(chartW / minLabelSlot));
  const labelEvery = Math.max(1, Math.ceil(allDays.length / maxLabels));

  allDays.forEach((d, i) => {
    const bwRaw = barW * 0.7;
    const bw = Math.min(bwRaw, maxBarPx);
    const x = padding.left + i * barW + (barW - bw) / 2;
    const totalBarH = (d.count / maxCount) * chartH;

    if (d.count > 0 && hasModelData && dailyModelCounts[d.date]) {
      // Stacked bar: render segments bottom-up
      const segments = dailyModelCounts[d.date];
      let yOffset = 0;
      segments.forEach((seg, si) => {
        const segH = (seg.count / maxCount) * chartH;
        const key = seg.model + '|' + (seg.isLocal ? '1' : '0');
        const color = modelColorMap[key] || 'var(--accent)';
        const segY = padding.top + chartH - yOffset - segH;
        const isTop = si === segments.length - 1;
        bars += `<rect class="bar-segment" x="${x}" y="${segY}" width="${bw}" height="${segH}" rx="${isTop ? 2 : 0}" fill="${color}"><title>${d.date}: ${seg.model} (${seg.isLocal ? 'local' : 'API'}) — ${seg.count}</title></rect>`;
        yOffset += segH;
      });
    } else if (d.count > 0) {
      // Fallback: single-color bar
      bars += `<rect class="bar" x="${x}" y="${padding.top + chartH - totalBarH}" width="${bw}" height="${totalBarH}" rx="2"><title>${d.date}: ${d.count}</title></rect>`;
    }

    if (i % labelEvery === 0) {
      bars += `<text x="${padding.left + i * barW + barW / 2}" y="${h - 4}" text-anchor="middle">${d.label}</text>`;
    }
  });

  // Legend for model types
  let legendSvg = '';
  if (hasModelData) {
    const legendItems = [];
    for (const [key, color] of Object.entries(modelColorMap)) {
      if (!key.includes('|')) continue; // skip naked model name keys
      const model = key.slice(0, key.lastIndexOf('|'));
      legendItems.push({ label: model, color });
    }
    let lx = padding.left;
    for (const item of legendItems) {
      legendSvg += `<rect x="${lx}" y="${h + 4}" width="8" height="8" rx="2" fill="${item.color}"/>`;
      legendSvg += `<text x="${lx + 11}" y="${h + 12}" class="chart-legend-label">${item.label}</text>`;
      lx += item.label.length * 5.5 + 22;
    }
  }

  return `<svg class="bar-chart${hasModelData ? ' stacked' : ''}" viewBox="0 0 ${svgWidth} ${totalH}" preserveAspectRatio="none">
    ${gridLines}
    <line class="axis" x1="${padding.left}" y1="${padding.top + chartH}" x2="${svgWidth - padding.right}" y2="${padding.top + chartH}"/>
    ${bars}
    ${legendSvg}
  </svg>`;
}

function renderModelDonut(modelCounts) {
  if (!modelCounts || Object.keys(modelCounts).length === 0) {
    return `<p style="color:var(--text-hint);font-size:12px">${t('analytics.no_data')}</p>`;
  }

  const fallbackColors = ['#22D3EE', '#818CF8', '#10B981', '#F59E0B', '#8B5CF6', '#EC4899'];
  const entries = Object.entries(modelCounts).sort((a, b) => b[1] - a[1]);
  const total = entries.reduce((s, e) => s + e[1], 0);

  const cx = 90, cy = 90, r = 70, innerR = 45;
  let paths = '';
  const legend = [];

  // Single model: render full circle instead of degenerate arc
  if (entries.length === 1) {
    const [model, count] = entries[0];
    const color = _modelColorMap[model] || fallbackColors[0];
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
      const color = _modelColorMap[model] || fallbackColors[i % fallbackColors.length];
      paths += `<path d="M${x1},${y1} A${r},${r} 0 ${largeArc} 1 ${x2},${y2} L${ix1},${iy1} A${innerR},${innerR} 0 ${largeArc} 0 ${ix2},${iy2} Z" fill="${color}"/>`;
      legend.push(`<span class="donut-legend-item"><span class="donut-legend-dot" style="background:${color}"></span>${model} (${count})</span>`);
      startAngle = endAngle;
    });
  }

  return `<svg class="donut-chart" viewBox="0 0 180 180" preserveAspectRatio="xMidYMid meet">${paths}</svg>
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

function _fitDailyChart(root, dailyCounts, dailyModelCounts) {
  const wrap = root.querySelector('.chart-card.full-width .chart-container');
  if (!wrap || !dailyCounts) return;
  const w = wrap.clientWidth;
  if (w > 0) wrap.innerHTML = renderDailyChart(dailyCounts, dailyModelCounts, w);
}

function renderBenchmarkTable(benchmarks) {
  const models = Object.entries(benchmarks);

  // Sort by current column (_benchmarkSort defaults to speed descending)
  models.sort((a, b) => {
    let va, vb;
    switch (_benchmarkSort.column) {
      case 'model':
        return _benchmarkSort.ascending
          ? a[0].toLowerCase().localeCompare(b[0].toLowerCase())
          : b[0].toLowerCase().localeCompare(a[0].toLowerCase());
      case 'count':
        va = a[1].count; vb = b[1].count; break;
      case 'speed':
        va = a[1].speedRatio > 0 ? 1 / a[1].speedRatio : 0;
        vb = b[1].speedRatio > 0 ? 1 / b[1].speedRatio : 0;
        break;
      case 'wpm':
        va = a[1].wordsPerMin || 0; vb = b[1].wordsPerMin || 0; break;
      default:
        va = 0; vb = 0;
    }
    return _benchmarkSort.ascending ? va - vb : vb - va;
  });

  let rows = models.map(([model, s]) => {
    const factor = s.speedRatio > 0 ? 1 / s.speedRatio : 0;
    const speed = factor > 0 ? `${factor.toFixed(1)}x` : '—';
    const speedClass = factor >= 2 ? 'fast' : factor >= 1 ? 'medium' : 'slow';
    const color = _modelColorMap[model] || '#888';
    return `<tr>
      <td class="bench-model"><span class="model-color-dot" style="background:${color}"></span>${model}</td>
      <td class="bench-count">${s.count}</td>
      <td class="bench-speed ${speedClass}">${speed}</td>
      <td>${s.wordsPerMin > 0 ? Math.round(s.wordsPerMin) : '—'}</td>
    </tr>`;
  }).join('');

  const hdr = (col, label) => {
    const active = _benchmarkSort.column === col ? ' active' : '';
    const arrow = _benchmarkSort.column === col
      ? `<span class="sort-arrow">${_benchmarkSort.ascending ? '▲' : '▼'}</span>`
      : '';
    return `<th class="sortable${active}" onclick="sortBenchmarkTable('${col}')">${label}${arrow}</th>`;
  };

  return `<table class="benchmark-table">
    <thead><tr>
      ${hdr('model', t('analytics.bench_model'))}
      ${hdr('count', t('analytics.bench_count'))}
      ${hdr('speed', t('analytics.bench_speed'))}
      ${hdr('wpm', t('analytics.bench_wpm'))}
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

function sortBenchmarkTable(column) {
  if (_benchmarkSort.column === column) {
    _benchmarkSort.ascending = !_benchmarkSort.ascending;
  } else {
    _benchmarkSort.column = column;
    _benchmarkSort.ascending = false;
  }
  if (!_analyticsData || !_analyticsData.modelBenchmarks) return;
  const container = document.querySelector('.benchmark-table')?.closest('.chart-container');
  if (container) container.innerHTML = renderBenchmarkTable(_analyticsData.modelBenchmarks);
}

function renderMonthlyCosts(monthlyCosts) {
  const months = Object.entries(monthlyCosts).sort((a, b) => b[0].localeCompare(a[0]));
  const currentMonth = new Date().toISOString().slice(0, 7);
  let rows = months.map(([month, cost]) => {
    const isCurrent = month === currentMonth;
    return `<tr class="${isCurrent ? 'current-month' : ''}">
      <td>${month}</td>
      <td>${'$' + cost.toFixed(4)}</td>
    </tr>`;
  }).join('');

  return `<table class="monthly-costs-table">
    <thead><tr>
      <th>${t('analytics.month')}</th>
      <th>${t('analytics.cost')}</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

function confirmResetStatistics() {
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `<div class="modal-dialog">
    <div class="modal-title">${t('analytics.reset_title')}</div>
    <div class="modal-text">${t('analytics.reset_confirm')}</div>
    <div class="modal-actions">
      <button class="btn-secondary" onclick="this.closest('.modal-overlay').remove()">${t('analytics.reset_cancel')}</button>
      <button class="btn-danger" onclick="doResetStatistics()">${t('analytics.reset_confirm_btn')}</button>
    </div>
  </div>`;
  document.body.appendChild(overlay);
}

async function doResetStatistics() {
  try {
    const raw = await window.resetStatistics();
    const result = typeof raw === 'string' ? JSON.parse(raw) : raw;
    document.querySelector('.modal-overlay')?.remove();
    if (result && result.ok) {
      loadAnalytics();
    }
  } catch (e) {
    document.querySelector('.modal-overlay')?.remove();
    console.error('Reset failed:', e);
    showToast(t('resetError'), true);
  }
}

function _initAnalyticsResize() {
  if (_analyticsResizeObserver) return;
  const container = document.getElementById('analytics-content');
  if (!container) return;
  let resizeTimer = null;
  _analyticsResizeObserver = new ResizeObserver(() => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { // DevSkim: ignore DS172411 — debounce with constant delay
      if (_analyticsData) _fitDailyChart(container, _analyticsData.dailyCounts, _analyticsData.dailyModelCounts);
    }, 150);
  });
  _analyticsResizeObserver.observe(container);
}
