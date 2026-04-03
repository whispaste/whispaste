package main

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/models"
)

type dailyModelCount struct {
	Model   string `json:"model"`
	IsLocal bool   `json:"isLocal"`
	Count   int    `json:"count"`
}

// GetAnalytics computes usage statistics for a given time period.
// Results are cached for 2 seconds to avoid recomputation on rapid refreshes.
// Reads from the daily_stats aggregation table instead of scanning history_entries.
func (h *History) GetAnalytics(periodDays int) map[string]interface{} {
	if h.db == nil {
		return map[string]interface{}{}
	}

	if data := func() map[string]interface{} {
		h.mu.Lock()
		defer h.mu.Unlock()
		if h.cache != nil {
			if c, ok := h.cache[periodDays]; ok && time.Now().Before(c.validUntil) {
				return c.data
			}
		}
		return nil
	}(); data != nil {
		return data
	}

	var rows *sql.Rows
	var err error
	if periodDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -periodDays).Format("2006-01-02")
		rows, err = h.db.Query(`SELECT date, model, is_local, count, total_duration_sec, total_processing_sec, total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m FROM daily_stats WHERE date >= ?`, cutoff)
	} else {
		rows, err = h.db.Query(`SELECT date, model, is_local, count, total_duration_sec, total_processing_sec, total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m FROM daily_stats`)
	}
	if err != nil {
		logError("Analytics query: %v", err)
		return map[string]interface{}{}
	}
	defer rows.Close()

	var totalEntries, localEntries, apiEntries int
	var totalDuration, totalCost, localDuration float64
	var totalProcessingDuration float64
	var totalWords float64
	dailyCounts := map[string]int{}
	dailyModelCounts := map[string][]dailyModelCount{}
	modelCounts := map[string]int{}
	durationBuckets := map[string]int{"<15s": 0, "15-30s": 0, "30-60s": 0, "1-3m": 0, ">3m": 0}
	monthlyCosts := map[string]float64{}

	type modelStats struct {
		Count      int
		Duration   float64
		Processing float64
		Words      float64
	}
	modelBenchmarks := map[string]*modelStats{}

	for rows.Next() {
		var date, model string
		var isLocal, count, durU15, dur1530, dur3060, dur13m, durO3m int
		var durSec, procSec, words float64
		var costUSD float64
		if err := rows.Scan(&date, &model, &isLocal, &count, &durSec, &procSec, &words, &costUSD, &durU15, &dur1530, &dur3060, &dur13m, &durO3m); err != nil {
			logWarn("Analytics row scan: %v", err)
			continue
		}

		totalEntries += count
		totalDuration += durSec
		totalCost += costUSD
		totalProcessingDuration += procSec
		totalWords += words

		if isLocal == 1 {
			localEntries += count
			localDuration += durSec
		} else {
			apiEntries += count
		}

		dailyCounts[date] += count

		model = normalizeModelName(model)
		dailyModelCounts[date] = append(dailyModelCounts[date], dailyModelCount{
			Model:   model,
			IsLocal: isLocal == 1,
			Count:   count,
		})
		modelCounts[model] += count

		mb, ok := modelBenchmarks[model]
		if !ok {
			mb = &modelStats{}
			modelBenchmarks[model] = mb
		}
		mb.Count += count
		mb.Duration += durSec
		mb.Processing += procSec
		mb.Words += words

		if len(date) >= 7 {
			monthlyCosts[date[:7]] += costUSD
		}

		durationBuckets["<15s"] += durU15
		durationBuckets["15-30s"] += dur1530
		durationBuckets["30-60s"] += dur3060
		durationBuckets["1-3m"] += dur13m
		durationBuckets[">3m"] += durO3m
	}
	if err := rows.Err(); err != nil {
		logWarn("Analytics rows iteration: %v", err)
	}

	savings := (localDuration / 60.0) * WhisperCostPerMinute
	avgDuration := safeDiv(totalDuration, float64(totalEntries))

	// Get real min/max duration from history_entries
	var minDuration, maxDuration float64
	minMaxQuery := `SELECT COALESCE(MIN(duration_sec), 0), COALESCE(MAX(duration_sec), 0) FROM history_entries`
	if periodDays > 0 {
		cutoff := time.Now().AddDate(0, 0, -periodDays).Format("2006-01-02")
		minMaxQuery += ` WHERE substr(timestamp, 1, 10) >= ?`
		err = h.db.QueryRow(minMaxQuery, cutoff).Scan(&minDuration, &maxDuration)
	} else {
		err = h.db.QueryRow(minMaxQuery).Scan(&minDuration, &maxDuration)
	}
	if err != nil {
		logDebug("Analytics min/max duration: %v", err)
		minDuration = avgDuration
		maxDuration = avgDuration
	}

	benchmarks := map[string]map[string]interface{}{}
	for m, s := range modelBenchmarks {
		benchmarks[m] = map[string]interface{}{
			"count":       s.Count,
			"duration":    s.Duration,
			"processing":  s.Processing,
			"words":       s.Words,
			"speedRatio":  safeDiv(s.Processing, s.Duration),
			"wordsPerMin": safeDiv(s.Words, s.Duration/60.0),
		}
	}

	// Time saved vs typing at 40 WPM
	typingMin := totalWords / 40.0
	dictationMin := totalDuration / 60.0
	timeSaved := typingMin - dictationMin
	if timeSaved < 0 {
		timeSaved = 0
	}

	// Overall average speed ratio (audio duration / processing time = realtime factor)
	avgSpeedRatio := safeDiv(totalDuration, totalProcessingDuration)

	result := map[string]interface{}{
		"totalEntries":          totalEntries,
		"localEntries":          localEntries,
		"apiEntries":            apiEntries,
		"totalDuration":         totalDuration,
		"totalCost":             totalCost,
		"savings":               savings,
		"dailyCounts":           dailyCounts,
		"dailyModelCounts":      dailyModelCounts,
		"modelCounts":           modelCounts,
		"durationBuckets":       durationBuckets,
		"avgDuration":           avgDuration,
		"minDuration":           minDuration,
		"maxDuration":           maxDuration,
		"avgProcessingDuration": safeDiv(totalProcessingDuration, float64(totalEntries)),
		"totalProcessingTime":   totalProcessingDuration,
		"modelBenchmarks":       benchmarks,
		"monthlyCosts":          monthlyCosts,
		"totalWords":            totalWords,
		"avgWordsPerEntry":      safeDiv(totalWords, float64(totalEntries)),
		"timeSaved":             timeSaved,
		"avgSpeedRatio":         avgSpeedRatio,
	}

	// Data audit: compare daily_stats totals against history_entries (rate-limited)
	h.auditDailyStatsThrottled()

	func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		if h.cache == nil {
			h.cache = make(map[int]*analyticsCache)
		}
		h.cache[periodDays] = &analyticsCache{data: result, validUntil: time.Now().Add(2 * time.Second)}
	}()

	return result
}

// ResetStatistics clears all daily_stats data and the analytics cache.
func (h *History) ResetStatistics() error {
	if h.db == nil {
		return fmt.Errorf("database not available")
	}
	_, err := h.db.Exec("DELETE FROM daily_stats")
	if err != nil {
		logError("ResetStatistics: %v", err)
		return fmt.Errorf("ResetStatistics: %w", err)
	}
	h.invalidateCache()
	logInfo("Statistics reset: daily_stats cleared")
	return nil
}

// normalizeModelName maps raw model IDs (e.g. "whisper-small") to their
// display names (e.g. "Whisper Small") using the model registry. Cloud
// provider models and other unrecognised strings are returned as-is.
func normalizeModelName(raw string) string {
	if raw == "" || strings.EqualFold(raw, "unknown") {
		return "Unknown"
	}
	if info := models.Find(raw); info != nil {
		return info.Name
	}
	// Fuzzy: check if raw is a truncated version of a known model ID.
	// Only match if raw is ≥80% of the ID length (prevents false positives).
	lower := strings.ToLower(raw)
	for _, m := range models.Available {
		id := strings.ToLower(m.ID)
		if len(lower) >= len(id)*8/10 && strings.HasPrefix(id, lower) {
			return m.Name
		}
	}
	return raw
}

func safeDiv(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}

// auditDailyStatsThrottled runs the audit at most once every 5 minutes.
func (h *History) auditDailyStatsThrottled() {
	h.mu.Lock()
	if time.Since(h.lastAuditTime) < 5*time.Minute {
		h.mu.Unlock()
		return
	}
	h.lastAuditTime = time.Now()
	h.mu.Unlock()
	h.auditDailyStats()
}

// auditDailyStats logs discrepancies between daily_stats and history_entries for the last 7 days.
func (h *History) auditDailyStats() {
	cutoff := time.Now().AddDate(0, 0, -7).Format("2006-01-02")

	// Get daily_stats totals per date
	statsRows, err := h.db.Query(`SELECT date, SUM(count) FROM daily_stats WHERE date >= ? GROUP BY date`, cutoff)
	if err != nil {
		logDebug("Audit daily_stats query: %v", err)
		return
	}
	statsTotals := map[string]int{}
	for statsRows.Next() {
		var date string
		var count int
		if err := statsRows.Scan(&date, &count); err == nil {
			statsTotals[date] = count
		}
	}
	statsRows.Close()

	// Get history_entries counts per date
	entryRows, err := h.db.Query(`SELECT substr(timestamp, 1, 10) as date, COUNT(*) FROM history_entries WHERE substr(timestamp, 1, 10) >= ? GROUP BY date`, cutoff)
	if err != nil {
		logDebug("Audit history_entries query: %v", err)
		return
	}
	entryTotals := map[string]int{}
	for entryRows.Next() {
		var date string
		var count int
		if err := entryRows.Scan(&date, &count); err == nil {
			entryTotals[date] = count
		}
	}
	entryRows.Close()

	// Compare and log discrepancies
	allDates := map[string]bool{}
	for d := range statsTotals {
		allDates[d] = true
	}
	for d := range entryTotals {
		allDates[d] = true
	}
	for date := range allDates {
		sc := statsTotals[date]
		ec := entryTotals[date]
		if sc != ec {
			logDebug("Stats audit %s: daily_stats=%d history_entries=%d (diff=%d)", date, sc, ec, sc-ec)
		}
	}
}
