package main

import (
	"database/sql"
	"fmt"
	"time"
)

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

		if model == "" {
			model = "unknown"
		}
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

	result := map[string]interface{}{
		"totalEntries":          totalEntries,
		"localEntries":          localEntries,
		"apiEntries":            apiEntries,
		"totalDuration":         totalDuration,
		"totalCost":             totalCost,
		"savings":               savings,
		"dailyCounts":           dailyCounts,
		"modelCounts":           modelCounts,
		"durationBuckets":       durationBuckets,
		"avgDuration":           avgDuration,
		"minDuration":           avgDuration, // approximation from aggregates
		"maxDuration":           avgDuration, // approximation from aggregates
		"avgProcessingDuration": safeDiv(totalProcessingDuration, float64(totalEntries)),
		"totalProcessingTime":   totalProcessingDuration,
		"modelBenchmarks":       benchmarks,
		"monthlyCosts":          monthlyCosts,
		"totalWords":            totalWords,
		"avgWordsPerEntry":      safeDiv(totalWords, float64(totalEntries)),
	}

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

func safeDiv(a, b float64) float64 {
	if b == 0 {
		return 0
	}
	return a / b
}
