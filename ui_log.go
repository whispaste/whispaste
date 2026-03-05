package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	webview "github.com/webview/webview_go"
)

var (
	logViewerWindow webview.WebView
	logViewerOpen   bool
	logViewerMu     sync.Mutex
)

// ShowLogViewer opens (or focuses) the log viewer window.
func ShowLogViewer() {
	logViewerMu.Lock()
	if logViewerOpen {
		logDebug("ShowLogViewer: already open, skipping")
		logViewerMu.Unlock()
		return
	}
	logViewerOpen = true
	logViewerMu.Unlock()
	logDebug("ShowLogViewer: opening log viewer")

	go func() {
		w := webview.New(true)
		if w == nil {
			logWarn("Failed to create log viewer webview")
			logViewerMu.Lock()
			logViewerOpen = false
			logViewerMu.Unlock()
			return
		}
		defer w.Destroy()

		logViewerMu.Lock()
		logViewerWindow = w
		logViewerMu.Unlock()

		defer func() {
			logViewerMu.Lock()
			logViewerWindow = nil
			logViewerOpen = false
			logViewerMu.Unlock()
			logDebug("ShowLogViewer: closed, state reset")
		}()

		w.SetTitle("WhisPaste — Log Viewer")
		w.SetSize(900, 600, webview.HintNone)
		w.SetSize(600, 400, webview.HintMin)

		w.Bind("readLogLines", func(maxLines int) string {
			return readLastLogLines(maxLines)
		})

		w.SetHtml(logViewerHTML())
		w.Run()
	}()
}

// readLastLogLines reads the last N lines from the log file and returns them as a JSON array.
func readLastLogLines(maxLines int) string {
	if maxLines <= 0 {
		return "[]"
	}
	dir, err := configDir()
	if err != nil {
		logWarn("readLastLogLines: config dir error: %v", err)
		return "[]"
	}
	path := filepath.Join(dir, logFile)

	f, err := os.Open(path)
	if err != nil {
		logWarn("readLastLogLines: open error: %v", err)
		return "[]"
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		logWarn("readLastLogLines: scanner error: %v", err)
	}

	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}

	encoded, err := json.Marshal(lines)
	if err != nil {
		logWarn("readLastLogLines: json marshal error: %v", err)
		return "[]"
	}
	return string(encoded)
}

// logViewerHTML returns the self-contained HTML for the log viewer window.
func logViewerHTML() string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Log Viewer</title>
<style>
  :root {
    --bg-primary: #0f172a;
    --bg-secondary: #1e293b;
    --bg-toolbar: #1e293b;
    --bg-status: #0f172a;
    --border-color: #334155;
    --text-primary: #e2e8f0;
    --text-secondary: #94a3b8;
    --color-dbg: #64748b;
    --color-inf: #06b6d4;
    --color-wrn: #eab308;
    --color-err: #ef4444;
    --font-mono: 'Cascadia Code', 'Cascadia Mono', Consolas, 'Courier New', monospace;
  }

  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: var(--font-mono);
    background: var(--bg-primary);
    color: var(--text-primary);
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    font-size: 13px;
  }

  .toolbar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 12px;
    background: var(--bg-toolbar);
    border-bottom: 1px solid var(--border-color);
    flex-shrink: 0;
    flex-wrap: wrap;
  }

  .filters {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .filters label {
    display: flex;
    align-items: center;
    gap: 4px;
    cursor: pointer;
    padding: 3px 8px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: 600;
    border: 1px solid var(--border-color);
    user-select: none;
    transition: opacity 0.15s;
  }
  .filters label:has(input:not(:checked)) { opacity: 0.4; }
  .filters label input { display: none; }

  .filter-dbg { color: var(--color-dbg); border-color: var(--color-dbg); }
  .filter-inf { color: var(--color-inf); border-color: var(--color-inf); }
  .filter-wrn { color: var(--color-wrn); border-color: var(--color-wrn); }
  .filter-err { color: var(--color-err); border-color: var(--color-err); }

  #searchBox {
    flex: 1;
    min-width: 140px;
    padding: 5px 10px;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    background: var(--bg-primary);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 12px;
    outline: none;
    transition: border-color 0.15s;
  }
  #searchBox:focus { border-color: var(--color-inf); }
  #searchBox::placeholder { color: var(--text-secondary); }

  .controls {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .controls label {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 12px;
    color: var(--text-secondary);
    cursor: pointer;
    user-select: none;
  }
  .controls label input {
    accent-color: var(--color-inf);
  }

  #clearBtn {
    padding: 4px 10px;
    border: 1px solid var(--border-color);
    border-radius: 4px;
    background: transparent;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 12px;
    cursor: pointer;
    transition: all 0.15s;
  }
  #clearBtn:hover {
    background: var(--bg-primary);
    color: var(--text-primary);
    border-color: var(--text-secondary);
  }

  .log-area {
    flex: 1;
    overflow-y: auto;
    padding: 4px 0;
    scrollbar-width: thin;
    scrollbar-color: var(--border-color) transparent;
  }

  .log-line {
    padding: 2px 12px;
    white-space: pre-wrap;
    word-break: break-all;
    line-height: 1.5;
    border-left: 3px solid transparent;
  }
  .log-line:hover { background: rgba(255,255,255,0.03); }

  .log-line.level-dbg { border-left-color: var(--color-dbg); color: var(--color-dbg); }
  .log-line.level-inf { border-left-color: var(--color-inf); }
  .log-line.level-wrn { border-left-color: var(--color-wrn); }
  .log-line.level-err { border-left-color: var(--color-err); background: rgba(239,68,68,0.06); }

  .badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: 3px;
    margin-right: 6px;
    letter-spacing: 0.5px;
  }
  .badge-dbg { background: rgba(100,116,139,0.2); color: var(--color-dbg); }
  .badge-inf { background: rgba(6,182,212,0.15); color: var(--color-inf); }
  .badge-wrn { background: rgba(234,179,8,0.15); color: var(--color-wrn); }
  .badge-err { background: rgba(239,68,68,0.15); color: var(--color-err); }

  mark {
    background: rgba(234,179,8,0.3);
    color: inherit;
    border-radius: 2px;
    padding: 0 1px;
  }

  .status-bar {
    display: flex;
    justify-content: space-between;
    padding: 4px 12px;
    background: var(--bg-status);
    border-top: 1px solid var(--border-color);
    font-size: 11px;
    color: var(--text-secondary);
    flex-shrink: 0;
  }
</style>
</head>
<body>
  <div class="toolbar">
    <div class="filters">
      <label class="filter-dbg"><input type="checkbox" id="filterDbg" checked> DBG</label>
      <label class="filter-inf"><input type="checkbox" id="filterInf" checked> INF</label>
      <label class="filter-wrn"><input type="checkbox" id="filterWrn" checked> WRN</label>
      <label class="filter-err"><input type="checkbox" id="filterErr" checked> ERR</label>
    </div>
    <input type="text" id="searchBox" placeholder="Search logs...">
    <div class="controls">
      <label><input type="checkbox" id="autoScroll" checked> Auto-scroll</label>
      <button id="clearBtn">Clear</button>
      <span id="lineCount" style="color:var(--text-secondary)">0 lines</span>
    </div>
  </div>
  <div id="logArea" class="log-area"></div>
  <div class="status-bar">
    <span id="statusText">Loading...</span>
    <span id="lastRefresh"></span>
  </div>
<script>
(function() {
  let allLines = [];
  let autoRefreshInterval = null;

  const area = document.getElementById('logArea');
  const searchBox = document.getElementById('searchBox');
  const filterDbg = document.getElementById('filterDbg');
  const filterInf = document.getElementById('filterInf');
  const filterWrn = document.getElementById('filterWrn');
  const filterErr = document.getElementById('filterErr');
  const autoScrollCb = document.getElementById('autoScroll');
  const lineCountEl = document.getElementById('lineCount');
  const statusText = document.getElementById('statusText');
  const lastRefresh = document.getElementById('lastRefresh');

  function extractLevel(line) {
    if (line.includes('[DBG]')) return 'dbg';
    if (line.includes('[INF]')) return 'inf';
    if (line.includes('[WRN]')) return 'wrn';
    if (line.includes('[ERR]')) return 'err';
    return 'inf';
  }

  function escapeHtml(text) {
    const d = document.createElement('div');
    d.textContent = text;
    return d.innerHTML;
  }

  function highlightSearch(html, search) {
    if (!search) return html;
    const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const re = new RegExp('(' + escaped + ')', 'gi');
    return html.replace(re, '<mark>$1</mark>');
  }

  function renderLogs() {
    const search = searchBox.value.toLowerCase();
    const showDbg = filterDbg.checked;
    const showInf = filterInf.checked;
    const showWrn = filterWrn.checked;
    const showErr = filterErr.checked;

    const parts = [];
    let count = 0;
    for (const line of allLines) {
      const level = extractLevel(line);
      if (level === 'dbg' && !showDbg) continue;
      if (level === 'inf' && !showInf) continue;
      if (level === 'wrn' && !showWrn) continue;
      if (level === 'err' && !showErr) continue;
      if (search && !line.toLowerCase().includes(search)) continue;

      const badge = '<span class="badge badge-' + level + '">' + level.toUpperCase() + '</span>';
      let content = escapeHtml(line);
      if (search) content = highlightSearch(content, searchBox.value);
      parts.push('<div class="log-line level-' + level + '">' + badge + content + '</div>');
      count++;
    }
    area.innerHTML = parts.join('');
    lineCountEl.textContent = count + ' lines';
    lastRefresh.textContent = 'Updated: ' + new Date().toLocaleTimeString();
    statusText.textContent = allLines.length + ' total, ' + count + ' shown';

    if (autoScrollCb.checked) {
      area.scrollTop = area.scrollHeight;
    }
  }

  async function loadLogs() {
    try {
      const raw = await window.readLogLines(5000);
      allLines = JSON.parse(raw);
      renderLogs();
      statusText.textContent = allLines.length + ' lines loaded';
    } catch(e) {
      statusText.textContent = 'Error loading logs';
    }
    startAutoRefresh();
  }

  function startAutoRefresh() {
    if (autoRefreshInterval) clearInterval(autoRefreshInterval);
    autoRefreshInterval = setInterval(async () => {
      try {
        const raw = await window.readLogLines(5000);
        allLines = JSON.parse(raw);
        renderLogs();
      } catch(e) { /* ignore refresh errors */ }
    }, 2000);
  }

  searchBox.addEventListener('input', renderLogs);
  [filterDbg, filterInf, filterWrn, filterErr].forEach(cb => {
    cb.addEventListener('change', renderLogs);
  });
  document.getElementById('clearBtn').addEventListener('click', function() {
    allLines = [];
    renderLogs();
  });

  loadLogs();
})();
</script>
</body>
</html>`
}
