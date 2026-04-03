package main

import (
	"bytes"
	"crypto/md5"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	crashQueueDB      = "crash_queue.db"
	maxCrashQueue     = 500
	maxReportsPerHour = 50
	maxQueueAgeDays   = 30
	crashFlushEvery   = 60 * time.Second
	discordSendDelay  = 2 * time.Second
	crashDedupWindow  = 1 * time.Hour
	maxEmbedFieldLen  = 1024
)

var sensitiveMessagePatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)["']?(api[_-]?key|token|password|authorization)["']?\s*[:=]\s*['"]?[^\s'",}]+`),
	regexp.MustCompile(`(?i)\bbearer\s+[A-Za-z0-9._\-+/=]+\b`),
	regexp.MustCompile(`\bsk-[A-Za-z0-9][A-Za-z0-9\-_]{5,}\b`),
	regexp.MustCompile(`\bgsk_[A-Za-z0-9][A-Za-z0-9\-_]{5,}\b`),
	regexp.MustCompile(`\bsk-ant-[A-Za-z0-9\-_]{8,}\b`),
	regexp.MustCompile(`\bAIza[0-9A-Za-z\-_]{10,}\b`),
}

// CrashReporter queues and sends error reports via the configured relay.
// Reports are persisted in a local SQLite database so nothing is lost
// when the application is offline or crashes.
type CrashReporter struct {
	mu            sync.Mutex
	db            *sql.DB
	enabled       bool
	closed        atomic.Bool
	relayURL      string
	deviceID      string
	stopCh        chan struct{}
	ticker        *time.Ticker
	dedupMu       sync.Mutex
	dedupCache    map[string]time.Time
	hourCount     int
	hourResetTime time.Time
	cfg           *Config
}

// crashReport holds a single error report.
type crashReport struct {
	ID             string `json:"id"`
	Timestamp      int64  `json:"timestamp"`
	Type           string `json:"type"` // "error", "panic", "subprocess_crash"
	Severity       string `json:"severity"`
	Message        string `json:"message"`
	StackTrace     string `json:"stack_trace"`
	ProcessName    string `json:"process_name,omitempty"`
	AppVersion     string `json:"app_version"`
	BuildCommit    string `json:"build_commit,omitempty"`
	GoVersion      string `json:"go_version"`
	OS             string `json:"os"`
	Arch           string `json:"arch"`
	DeviceID       string `json:"device_id"`
	GPU            string `json:"gpu"`
	LocalSTT       bool   `json:"local_stt"`
	SmartMode      bool   `json:"smart_mode"`
	ConfigSnapshot string `json:"config_snapshot,omitempty"`
	Hash           string `json:"hash"`
	// Enrichment fields for better debugging
	AppState       string `json:"app_state,omitempty"`
	AppUptimeSec   int64  `json:"app_uptime_sec,omitempty"`
	GoroutineCount int    `json:"goroutine_count,omitempty"`
	HeapAllocMB    int    `json:"heap_alloc_mb,omitempty"`
	HeapSysMB      int    `json:"heap_sys_mb,omitempty"`
	NumGC          uint32 `json:"num_gc,omitempty"`
	RecentLogs     string `json:"recent_logs,omitempty"`
	InstallSource  string `json:"install_source,omitempty"`
}

type crashRelayPayload struct {
	Report crashReport            `json:"report"`
	Embed  map[string]interface{} `json:"embed"`
}

var (
	crashReporter     *CrashReporter
	crashReporterOnce sync.Once
)

// InitCrashReporter creates and starts the crash reporter singleton.
// Call after InitLogger and LoadConfig.
func InitCrashReporter(c *Config) {
	crashReporterOnce.Do(func() {
		cr := &CrashReporter{
			enabled:       c.GetErrorReportingEnabled(),
			dedupCache:    make(map[string]time.Time),
			stopCh:        make(chan struct{}),
			hourResetTime: time.Now().Add(time.Hour),
			cfg:           c,
		}
		crashReporter = cr

		if !cr.enabled {
			logInfo("Crash reporting: disabled")
			return
		}

		if err := cr.initDB(); err != nil {
			logWarn("Crash reporter DB init failed: %v (disabled)", err)
			cr.enabled = false
			return
		}

		cr.deviceID = deriveDeviceID()

		cr.relayURL = strings.TrimSpace(CrashRelayURL)
		if cr.relayURL != "" {
			logInfo("Crash reporting: enabled (relay configured)")
			cr.ticker = time.NewTicker(crashFlushEvery)
			go cr.senderLoop()
		} else {
			logInfo("Crash reporting: enabled (local queue only, no relay)")
		}
	})
}

// CloseCrashReporter flushes pending reports and shuts down.
func CloseCrashReporter() {
	cr := crashReporter
	if cr == nil {
		return
	}
	cr.closed.Store(true)
	if cr.ticker != nil {
		cr.ticker.Stop()
	}
	select {
	case <-cr.stopCh:
		// already closed
	default:
		close(cr.stopCh)
	}
	if cr.db != nil {
		if cr.relayURL != "" {
			cr.flush()
		}
		cr.db.Close()
	}
}

// SetCrashReportingEnabled toggles reporting at runtime.
func SetCrashReportingEnabled(enabled bool) {
	cr := crashReporter
	if cr == nil {
		return
	}
	cr.mu.Lock()
	cr.enabled = enabled
	cr.mu.Unlock()
}

// ---------- database ----------

func (cr *CrashReporter) initDB() error {
	dir, err := configDir()
	if err != nil {
		return err
	}
	dbPath := filepath.Join(dir, crashQueueDB)
	db, err := sql.Open("sqlite", dbPath+"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)")
	if err != nil {
		return fmt.Errorf("open crash db: %w", err)
	}
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS crash_queue (
			id          TEXT PRIMARY KEY,
			timestamp   INTEGER,
			type        TEXT,
			severity    TEXT,
			message     TEXT,
			stack_trace TEXT,
			process     TEXT,
			app_version TEXT,
			build_commit TEXT,
			go_version  TEXT,
			os          TEXT,
			arch        TEXT,
			device_id   TEXT,
			gpu         TEXT,
			local_stt   INTEGER,
			smart_mode  INTEGER,
			config_snapshot TEXT,
			hash        TEXT,
			created_at  INTEGER
		);
		CREATE INDEX IF NOT EXISTS idx_crash_hash ON crash_queue(hash);
		CREATE INDEX IF NOT EXISTS idx_crash_created ON crash_queue(created_at);
	`)
	if err != nil {
		db.Close()
		return fmt.Errorf("create crash schema: %w", err)
	}
	if _, err := db.Exec(`ALTER TABLE crash_queue ADD COLUMN config_snapshot TEXT`); err != nil &&
		!strings.Contains(strings.ToLower(err.Error()), "duplicate column name") {
		db.Close()
		return fmt.Errorf("migrate crash schema: %w", err)
	}

	// Prune old records.
	cutoff := time.Now().AddDate(0, 0, -maxQueueAgeDays).Unix()
	db.Exec("DELETE FROM crash_queue WHERE created_at < ?", cutoff)

	cr.db = db
	return nil
}

// ---------- capture ----------

// captureError queues an error report. Safe to call from any goroutine.
func (cr *CrashReporter) captureError(message, errType, severity string) {
	if cr == nil || cr.closed.Load() || !cr.enabled || cr.db == nil {
		return
	}

	stack := captureStack(4)
	message = sanitizeMessage(message)
	stack = sanitizeStackTrace(stack)

	r := cr.newReport(errType, severity, message, stack, "")
	cr.enqueue(r)
}

// capturePanic queues a panic report.
func (cr *CrashReporter) capturePanic(recovered interface{}) {
	if cr == nil || cr.closed.Load() || !cr.enabled || cr.db == nil {
		return
	}

	msg := sanitizeMessage(fmt.Sprintf("%v", recovered))
	stack := sanitizeStackTrace(captureStack(2))

	r := cr.newReport("panic", "critical", msg, stack, "")
	cr.enqueue(r)
}

// extractExitCode extracts the process exit code from a cmd.Wait() error.
func extractExitCode(err error) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

// captureSubprocessCrash records a subprocess crash.
func (cr *CrashReporter) captureSubprocessCrash(process string, exitCode int, stderr string) {
	if cr == nil || cr.closed.Load() || !cr.enabled || cr.db == nil {
		return
	}

	msg := fmt.Sprintf("%s exited with code %d", process, exitCode)
	if stderr != "" {
		if len(stderr) > 200 {
			stderr = stderr[:200]
		}
		msg += ": " + stderr
	}
	msg = sanitizeMessage(msg)
	stderr = sanitizeStackTrace(stderr)

	r := cr.newReport("subprocess_crash", "error", msg, stderr, process)
	cr.enqueue(r)
}

func (cr *CrashReporter) newReport(typ, severity, message, stack, process string) *crashReport {
	gpuStr := ""
	localSTT := false
	smartMode := false
	configSnapshot := ""
	if cr.cfg != nil {
		gpuStr = cr.cfg.GetGPUAcceleration()
		localSTT = cr.cfg.GetUseLocalSTT()
		smartMode = cr.cfg.GetSmartMode()
		configSnapshot = buildCrashConfigSnapshot(cr.cfg)
	}

	// Capture runtime diagnostics
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	recentLogs := ""
	if crashLogBuffer != nil {
		recentLogs = sanitizePaths(truncStr(crashLogBuffer.GetRecent(), 1500))
	}

	return &crashReport{
		ID:             newUUID(),
		Timestamp:      time.Now().Unix(),
		Type:           typ,
		Severity:       severity,
		Message:        message,
		StackTrace:     stack,
		ProcessName:    process,
		AppVersion:     AppVersion,
		BuildCommit:    BuildCommit,
		GoVersion:      runtime.Version(),
		OS:             runtime.GOOS,
		Arch:           runtime.GOARCH,
		DeviceID:       cr.deviceID,
		GPU:            gpuStr,
		LocalSTT:       localSTT,
		SmartMode:      smartMode,
		ConfigSnapshot: configSnapshot,
		Hash:           hashCrash(message, stack),
		AppState:       getCrashAppState(),
		AppUptimeSec:   int64(time.Since(crashAppStartTime).Seconds()),
		GoroutineCount: runtime.NumGoroutine(),
		HeapAllocMB:    int(memStats.Alloc / (1024 * 1024)),
		HeapSysMB:      int(memStats.Sys / (1024 * 1024)),
		NumGC:          memStats.NumGC,
		RecentLogs:     recentLogs,
		InstallSource:  getInstallSource(),
	}
}

func (cr *CrashReporter) enqueue(r *crashReport) {
	if cr.closed.Load() {
		return
	}

	var count int
	cr.db.QueryRow("SELECT COUNT(*) FROM crash_queue").Scan(&count)
	if count >= maxCrashQueue {
		cr.db.Exec("DELETE FROM crash_queue WHERE created_at = (SELECT MIN(created_at) FROM crash_queue)")
	}

	_, err := cr.db.Exec(`INSERT INTO crash_queue
		(id,timestamp,type,severity,message,stack_trace,process,
		 app_version,build_commit,go_version,os,arch,device_id,
		 gpu,local_stt,smart_mode,config_snapshot,hash,created_at)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
		r.ID, r.Timestamp, r.Type, r.Severity, r.Message, r.StackTrace, r.ProcessName,
		r.AppVersion, r.BuildCommit, r.GoVersion, r.OS, r.Arch, r.DeviceID,
		r.GPU, boolInt(r.LocalSTT), boolInt(r.SmartMode), r.ConfigSnapshot, r.Hash, time.Now().Unix(),
	)
	if err != nil {
		logWarn("Crash reporter enqueue failed: %v", err)
	}
}

// ---------- sender ----------

func (cr *CrashReporter) senderLoop() {
	for {
		select {
		case <-cr.stopCh:
			return
		case <-cr.ticker.C:
			if isNetworkAvailable() {
				cr.flush()
			}
		}
	}
}

func (cr *CrashReporter) flush() {
	if cr.db == nil || cr.relayURL == "" {
		return
	}
	cr.mu.Lock()
	defer cr.mu.Unlock()

	if cr.isRateLimited() {
		return
	}

	rows, err := cr.db.Query(`SELECT id,timestamp,type,severity,message,stack_trace,process,
		app_version,build_commit,go_version,os,arch,device_id,gpu,local_stt,smart_mode,config_snapshot,hash
		FROM crash_queue ORDER BY created_at ASC LIMIT 10`)
	if err != nil {
		return
	}
	defer rows.Close()

	var reports []crashReport
	for rows.Next() {
		var r crashReport
		var lstt, sm int
		if err := rows.Scan(&r.ID, &r.Timestamp, &r.Type, &r.Severity, &r.Message, &r.StackTrace,
			&r.ProcessName, &r.AppVersion, &r.BuildCommit, &r.GoVersion, &r.OS, &r.Arch,
			&r.DeviceID, &r.GPU, &lstt, &sm, &r.ConfigSnapshot, &r.Hash); err == nil {
			r.LocalSTT = lstt != 0
			r.SmartMode = sm != 0
			reports = append(reports, r)
		}
	}

	for _, r := range reports {
		// Dedup: skip if same hash was sent within the window.
		cr.dedupMu.Lock()
		last := cr.dedupCache[r.Hash]
		cr.dedupMu.Unlock()
		if !last.IsZero() && time.Since(last) < crashDedupWindow {
			cr.db.Exec("DELETE FROM crash_queue WHERE id = ?", r.ID)
			continue
		}

		if err := cr.sendToRelay(&r); err != nil {
			logDebug("Crash report relay failed: %v", err)
			continue // retry next cycle
		}

		cr.dedupMu.Lock()
		cr.dedupCache[r.Hash] = time.Now()
		cr.hourCount++
		cr.dedupMu.Unlock()

		cr.db.Exec("DELETE FROM crash_queue WHERE id = ?", r.ID)
		logDebug("Crash report relayed: type=%s severity=%s", r.Type, r.Severity)
		time.Sleep(discordSendDelay)
	}
}

func (cr *CrashReporter) sendToRelay(r *crashReport) error {
	payload := crashRelayPayload{
		Report: *r,
		Embed:  cr.buildEmbed(r),
	}
	data, _ := json.Marshal(payload)

	req, err := http.NewRequest(http.MethodPost, cr.relayURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if AppVersion != "" {
		req.Header.Set("User-Agent", fmt.Sprintf("WhisPaste/%s crash-reporter", AppVersion))
	}
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusAccepted && resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("relay %d: %s", resp.StatusCode, truncStr(string(body), 200))
	}
	return nil
}

func (cr *CrashReporter) buildEmbed(r *crashReport) map[string]interface{} {
	// Severity-based Discord embed styling
	var color int
	var emoji string
	switch r.Severity {
	case "critical":
		color = 0xDC2626 // bright red
		emoji = "🔴"
	case "error":
		color = 0xE97451 // orange-red
		emoji = "🟠"
	case "warning":
		color = 0xF59E0B // amber
		emoji = "🟡"
	default:
		color = 0x3B82F6 // blue (info)
		emoji = "ℹ️"
	}

	title := fmt.Sprintf("%s [%s] %s", emoji, strings.ToUpper(r.Type), r.Severity)
	msg := truncStr(r.Message, maxEmbedFieldLen)
	stack := truncStr(r.StackTrace, maxEmbedFieldLen)

	versionValue := r.AppVersion
	if versionValue == "" {
		versionValue = "dev"
	}

	// App context fields
	fields := []map[string]interface{}{
		{"name": "Version", "value": versionValue, "inline": true},
		{"name": "OS", "value": fmt.Sprintf("%s/%s", r.OS, r.Arch), "inline": true},
		{"name": "Go", "value": r.GoVersion, "inline": true},
		{"name": "Device", "value": r.DeviceID, "inline": true},
		{"name": "GPU", "value": r.GPU, "inline": true},
		{"name": "Install", "value": r.InstallSource, "inline": true},
	}
	if r.BuildCommit != "" {
		fields = append(fields, map[string]interface{}{
			"name": "Build", "value": truncStr(r.BuildCommit, 12), "inline": true,
		})
	}

	// Runtime diagnostics
	if r.AppState != "" || r.AppUptimeSec > 0 {
		uptimeStr := formatCrashUptime(r.AppUptimeSec)
		fields = append(fields, map[string]interface{}{
			"name":   "Runtime",
			"value":  fmt.Sprintf("State: **%s** | Uptime: %s | Goroutines: %d", r.AppState, uptimeStr, r.GoroutineCount),
			"inline": false,
		})
	}
	if r.HeapAllocMB > 0 {
		fields = append(fields, map[string]interface{}{
			"name":   "Memory",
			"value":  fmt.Sprintf("Heap: %d MB / %d MB | GC cycles: %d", r.HeapAllocMB, r.HeapSysMB, r.NumGC),
			"inline": false,
		})
	}

	if r.ConfigSnapshot != "" {
		fields = append(fields, map[string]interface{}{
			"name": "Runtime Config", "value": "```\n" + truncStr(r.ConfigSnapshot, maxEmbedFieldLen-8) + "\n```", "inline": false,
		})
	} else {
		fields = append(fields, map[string]interface{}{
			"name": "Runtime Config", "value": fmt.Sprintf("LocalSTT=%v SmartMode=%v", r.LocalSTT, r.SmartMode), "inline": false,
		})
	}
	if stack != "" {
		fields = append(fields, map[string]interface{}{
			"name": "Stack Trace", "value": "```\n" + stack + "\n```",
		})
	}
	if r.ProcessName != "" {
		fields = append(fields, map[string]interface{}{
			"name": "Process", "value": r.ProcessName, "inline": true,
		})
	}
	if r.RecentLogs != "" {
		// Show last ~5 lines to stay within embed limits
		logLines := strings.Split(strings.TrimSpace(r.RecentLogs), "\n")
		start := 0
		if len(logLines) > 5 {
			start = len(logLines) - 5
		}
		recentStr := strings.Join(logLines[start:], "\n")
		if len(recentStr) > 600 {
			recentStr = recentStr[len(recentStr)-600:]
		}
		fields = append(fields, map[string]interface{}{
			"name": "Recent Logs", "value": "```\n" + recentStr + "\n```",
		})
	}

	ts := time.Unix(r.Timestamp, 0).UTC().Format("2006-01-02 15:04:05 UTC")
	return map[string]interface{}{
		"title":       title,
		"description": msg,
		"color":       color,
		"fields":      fields,
		"footer":      map[string]interface{}{"text": fmt.Sprintf("ID: %s | %s", r.ID[:8], ts)},
	}
}

func formatCrashUptime(sec int64) string {
	if sec < 60 {
		return fmt.Sprintf("%ds", sec)
	}
	if sec < 3600 {
		return fmt.Sprintf("%dm %ds", sec/60, sec%60)
	}
	return fmt.Sprintf("%dh %dm", sec/3600, (sec%3600)/60)
}

func (cr *CrashReporter) isRateLimited() bool {
	cr.dedupMu.Lock()
	defer cr.dedupMu.Unlock()
	now := time.Now()
	if now.After(cr.hourResetTime) {
		cr.hourCount = 0
		cr.hourResetTime = now.Add(time.Hour)
	}
	return cr.hourCount >= maxReportsPerHour
}

// ---------- helpers ----------

func captureStack(skip int) string {
	buf := new(bytes.Buffer)
	pcs := make([]uintptr, 32)
	n := runtime.Callers(skip+2, pcs)
	frames := runtime.CallersFrames(pcs[:n])
	for {
		f, more := frames.Next()
		fmt.Fprintf(buf, "%s\n\t%s:%d\n", f.Function, f.File, f.Line)
		if !more {
			break
		}
	}
	return buf.String()
}

func hashCrash(message, stack string) string {
	h := md5.Sum([]byte(message + stack))
	return hex.EncodeToString(h[:])
}

// sanitizeMessage redacts known sensitive patterns.
func sanitizeMessage(s string) string {
	for _, pattern := range sensitiveMessagePatterns {
		if pattern.MatchString(s) {
			return "[REDACTED — contains sensitive data]"
		}
	}
	return sanitizePaths(s)
}

// sanitizeStackTrace removes user-identifying path components.
func sanitizeStackTrace(s string) string {
	return sanitizePaths(s)
}

func sanitizePaths(s string) string {
	if home := os.Getenv("USERPROFILE"); home != "" {
		s = strings.ReplaceAll(s, home, "<home>")
	}
	if home := os.Getenv("HOME"); home != "" {
		s = strings.ReplaceAll(s, home, "<home>")
	}
	if user := os.Getenv("USERNAME"); user != "" {
		s = strings.ReplaceAll(s, user, "<user>")
	}
	if user := os.Getenv("USER"); user != "" {
		s = strings.ReplaceAll(s, user, "<user>")
	}
	if appdata := os.Getenv("APPDATA"); appdata != "" {
		s = strings.ReplaceAll(s, appdata, "<appdata>")
	}
	return s
}

func buildCrashConfigSnapshot(cfg *Config) string {
	if cfg == nil {
		return ""
	}

	profile := compactCrashValue(cfg.GetActiveProfile(), "default", 32)
	mode := compactCrashValue(cfg.GetMode(), "push_to_talk", 24)
	gpu := compactCrashValue(cfg.GetGPUAcceleration(), "auto", 16)
	inputDevice := compactCrashValue(cfg.GetInputDevice(), "default", 32)
	language := compactCrashValue(cfg.GetLanguage(), "auto", 16)

	sttMode := "cloud"
	sttProvider := compactCrashValue(cfg.GetCloudSTTProvider(), "openai", 16)
	sttModel := compactCrashValue(cfg.GetModel(), "whisper-1", 32)
	sttLanguage := compactCrashValue(cfg.GetTranscriptionLanguage(), language, 16)
	if cfg.GetUseLocalSTT() {
		sttMode = "local"
		sttProvider = "whisper.cpp"
		sttModel = compactCrashValue(cfg.GetLocalModelID(), "whisper-base", 32)
		sttLanguage = compactCrashValue(cfg.GetEffectiveLocalTranscriptionLanguage(), "auto", 16)
	}

	smartEnabled := cfg.GetSmartMode()
	smartProvider := "off"
	smartModel := "-"
	if smartEnabled {
		switch provider := cfg.GetSmartModeProvider(); provider {
		case "local":
			smartProvider = "local"
			smartModel = compactCrashValue(cfg.GetLocalLLMModel(), "qwen2.5-0.5b", 32)
		case "cloud":
			smartProvider = compactCrashValue(cfg.GetCloudLLMProvider(), "openai", 16)
			smartModel = compactCrashValue(cfg.GetCloudLLMModel(), "default", 32)
		case "auto":
			smartProvider = "auto/" + compactCrashValue(cfg.GetCloudLLMProvider(), "openai", 16)
			if cloudModel := compactCrashValue(cfg.GetCloudLLMModel(), "", 32); cloudModel != "" {
				smartModel = cloudModel
			} else {
				smartModel = compactCrashValue(cfg.GetLocalLLMModel(), "qwen2.5-0.5b", 32)
			}
		default:
			smartProvider = compactCrashValue(provider, "auto", 24)
			smartModel = compactCrashValue(cfg.GetCloudLLMModel(), "default", 32)
		}
	}

	lines := []string{
		fmt.Sprintf("profile=%s | mode=%s | gpu=%s", profile, mode, gpu),
		fmt.Sprintf("stt=%s | provider=%s | model=%s | lang=%s", sttMode, sttProvider, sttModel, sttLanguage),
		fmt.Sprintf("smart=%t | provider=%s | model=%s | preset=%s | target=%s",
			smartEnabled,
			smartProvider,
			smartModel,
			compactCrashValue(cfg.GetSmartModePreset(), "cleanup", 24),
			compactCrashValue(cfg.GetSmartModeTarget(), "en", 12),
		),
		fmt.Sprintf("audio=device:%s | gain=%.2f | vad=%t(%.2f) | trim=%t",
			inputDevice,
			cfg.GetInputGain(),
			cfg.GetUseVAD(),
			cfg.GetVADSensitivity(),
			cfg.GetTrimSilence(),
		),
	}
	return sanitizePaths(strings.Join(lines, "\n"))
}

func compactCrashValue(value, fallback string, maxLen int) string {
	value = strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(value, "\r", " "), "\n", " "))
	if value == "" {
		value = fallback
	}
	return truncStr(value, maxLen)
}

// deriveDeviceID generates a stable anonymous device identifier.
func deriveDeviceID() string {
	hostname, _ := os.Hostname()
	h := md5.Sum([]byte(hostname + "_whispaste"))
	return hex.EncodeToString(h[:])[:12]
}

func newUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("%d-%d", time.Now().UnixNano(), os.Getpid())
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func isNetworkAvailable() bool {
	conn, err := net.DialTimeout("tcp", "discord.com:443", 3*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func truncStr(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// ── App state & uptime tracking for crash enrichment ──

var (
	crashAppStartTime = time.Now()

	crashAppStateMu sync.RWMutex
	crashAppState   = "idle"
)

// SetCrashAppState updates the app state visible to the crash reporter.
func SetCrashAppState(state string) {
	crashAppStateMu.Lock()
	crashAppState = state
	crashAppStateMu.Unlock()
}

func getCrashAppState() string {
	crashAppStateMu.RLock()
	defer crashAppStateMu.RUnlock()
	return crashAppState
}

// ── Log ring buffer for crash breadcrumbs ──

type logRingBuffer struct {
	mu    sync.Mutex
	lines []string
	pos   int
	size  int
}

var crashLogBuffer = &logRingBuffer{
	lines: make([]string, 20),
	size:  20,
}

func (rb *logRingBuffer) Add(line string) {
	rb.mu.Lock()
	rb.lines[rb.pos] = line
	rb.pos = (rb.pos + 1) % rb.size
	rb.mu.Unlock()
}

func (rb *logRingBuffer) GetRecent() string {
	rb.mu.Lock()
	defer rb.mu.Unlock()
	var sb strings.Builder
	for i := 0; i < rb.size; i++ {
		idx := (rb.pos + i) % rb.size
		if rb.lines[idx] != "" {
			sb.WriteString(rb.lines[idx])
		}
	}
	return sb.String()
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// getInstallSource returns "msix" for Store/MSIX installs, "standalone" otherwise.
func getInstallSource() string {
	if isStorePackage() {
		return "msix"
	}
	return "standalone"
}
