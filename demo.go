package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// EnableDemoMode swaps the real database for an in-memory demo database
// populated with realistic sample data for marketing screenshots.
func (h *History) EnableDemoMode() error {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.demoMode {
		return nil
	}

	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		return fmt.Errorf("demo db: %w", err)
	}
	if err := createHistoryTables(db); err != nil {
		db.Close()
		return fmt.Errorf("demo tables: %w", err)
	}

	seedDemoData(db)

	h.realDb = h.db
	h.db = db
	h.demoMode = true
	h.cache = nil
	logInfo("Demo mode enabled")
	return nil
}

// DisableDemoMode restores the real database.
func (h *History) DisableDemoMode() {
	h.mu.Lock()
	defer h.mu.Unlock()

	if !h.demoMode {
		return
	}

	if h.db != nil {
		h.db.Close()
	}
	h.db = h.realDb
	h.realDb = nil
	h.demoMode = false
	h.cache = nil
	logInfo("Demo mode disabled")
}

// IsDemoMode returns whether demo mode is active.
func (h *History) IsDemoMode() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.demoMode
}

// demoEntry is a compact struct for seeding demo data.
type demoEntry struct {
	text     string
	title    string
	lang     string
	model    string
	isLocal  bool
	durSec   float64
	procSec  float64
	tags     []string
	pinned   bool
	project  string // project name — resolved to ID during seeding
	daysAgo  int    // timestamp offset from now
	hoursAgo int
}

// seedDemoData populates an in-memory database with realistic entries.
func seedDemoData(db *sql.DB) {
	now := time.Now()

	// --- Projects ---
	projects := []struct {
		id   string
		name string
	}{
		{"proj-meeting", "Meeting Notes"},
		{"proj-blog", "Blog Posts"},
		{"proj-research", "Research"},
	}
	for _, p := range projects {
		db.Exec("INSERT INTO projects (id, name, created_at) VALUES (?, ?, ?)",
			p.id, p.name, now.AddDate(0, -1, 0).Format(time.RFC3339))
	}

	// --- Entries ---
	entries := []demoEntry{
		{
			text:     "We discussed the new onboarding flow and agreed to simplify the model selection step. Sarah will prepare mockups by Friday. The team also reviewed the latest user feedback from the beta testers, which was overwhelmingly positive about the local transcription quality.",
			title:    "Weekly standup – onboarding redesign",
			lang:     "en",
			model:    "whisper-1",
			isLocal:  false,
			durSec:   185.0,
			procSec:  3.2,
			tags:     []string{"meeting", "important"},
			pinned:   true,
			project:  "proj-meeting",
			daysAgo:  0,
			hoursAgo: 2,
		},
		{
			text:     "Die Quartalszahlen zeigen eine Steigerung von 15 % im Vergleich zum Vorjahr. Besonders die Region DACH hat stark performt. Wir sollten den Fokus weiterhin auf lokale Partnerschaften legen und die Marketingstrategie für Q3 überarbeiten.",
			title:    "Quartalsbericht Q2 – Zusammenfassung",
			lang:     "de",
			model:    "whisper-base",
			isLocal:  true,
			durSec:   120.0,
			procSec:  4.1,
			tags:     []string{"meeting", "report"},
			project:  "proj-meeting",
			daysAgo:  0,
			hoursAgo: 5,
		},
		{
			text:     "Top 5 productivity tips for remote workers: First, establish a dedicated workspace. Second, use time-blocking to structure your day. Third, take regular breaks using the Pomodoro technique. Fourth, minimize notification distractions. Fifth, end each day with a brief review of accomplishments.",
			title:    "Blog draft: Remote productivity tips",
			lang:     "en",
			model:    "whisper-small",
			isLocal:  true,
			durSec:   95.0,
			procSec:  5.8,
			tags:     []string{"draft", "blog"},
			project:  "proj-blog",
			daysAgo:  1,
			hoursAgo: 3,
		},
		{
			text:     "Notiz an mich selbst: Die Präsentation für Montag noch einmal überarbeiten. Die Folien zu den Wettbewerbsanalysen müssen aktualisiert werden. Außerdem den neuen Prototyp in die Demo einbauen.",
			title:    "Selbst-Erinnerung: Präsentation",
			lang:     "de",
			model:    "qwen2.5-0.5b",
			isLocal:  true,
			durSec:   28.0,
			procSec:  1.9,
			tags:     []string{"reminder"},
			daysAgo:  1,
			hoursAgo: 8,
		},
		{
			text:     "The research paper by Zhang et al. (2025) suggests that smaller language models with targeted fine-tuning can match GPT-4 performance on domain-specific tasks while running locally. Key finding: 0.5B parameter models achieve 94% accuracy on medical transcription when trained on specialty corpora.",
			title:    "Paper notes: Small LLMs for transcription",
			lang:     "en",
			model:    "whisper-1",
			isLocal:  false,
			durSec:   145.0,
			procSec:  2.8,
			tags:     []string{"research", "ai"},
			pinned:   true,
			project:  "proj-research",
			daysAgo:  2,
			hoursAgo: 1,
		},
		{
			text:     "Customer interview with Acme Corp: They love the offline transcription feature. Main pain point is the initial model download time. Suggestion: show estimated download time upfront. They process about 200 dictations per week across their legal team of 12 people.",
			title:    "Customer interview – Acme Corp",
			lang:     "en",
			model:    "whisper-1",
			isLocal:  false,
			durSec:   340.0,
			procSec:  5.1,
			tags:     []string{"meeting", "feedback"},
			project:  "proj-meeting",
			daysAgo:  3,
			hoursAgo: 4,
		},
		{
			text:     "Einkaufsliste: Milch, Brot, Käse, Tomaten, Olivenöl, frischer Basilikum, Hähnchenbrust und Zitronen. Außerdem Spülmaschinentabs und Müllbeutel nicht vergessen.",
			title:    "Einkaufsliste",
			lang:     "de",
			model:    "whisper-base",
			isLocal:  true,
			durSec:   18.0,
			procSec:  1.2,
			tags:     []string{"personal"},
			daysAgo:  3,
			hoursAgo: 10,
		},
		{
			text:     "Sprint retrospective: What went well – deployment pipeline is now fully automated. What to improve – code review turnaround time still averaging 48 hours, target is 24. Action items: implement PR size limits, add auto-assignment for reviewers.",
			title:    "Sprint retro – automation wins",
			lang:     "en",
			model:    "whisper-small",
			isLocal:  true,
			durSec:   210.0,
			procSec:  8.5,
			tags:     []string{"meeting", "engineering"},
			project:  "proj-meeting",
			daysAgo:  5,
			hoursAgo: 2,
		},
		{
			text:     "Die neue Studie zur Sprachverarbeitung zeigt interessante Ergebnisse im Bereich der Echtzeit-Transkription. Besonders die Kombination aus Voice Activity Detection und Streaming-Inference reduziert die Latenz um bis zu 60 Prozent gegenüber Batch-Verarbeitung.",
			title:    "Forschungsnotiz: Echtzeit-STT",
			lang:     "de",
			model:    "qwen3.5-0.8b",
			isLocal:  true,
			durSec:   88.0,
			procSec:  6.2,
			tags:     []string{"research", "ai"},
			project:  "proj-research",
			daysAgo:  6,
			hoursAgo: 3,
		},
		{
			text:     "Voice memo: Remember to follow up with the design team about the new icon set. The current icons don't scale well at smaller sizes. Also need to finalize the color palette for dark mode – the contrast ratios on some buttons are below WCAG AA standards.",
			title:    "Voice memo: Design follow-ups",
			lang:     "en",
			model:    "whisper-1",
			isLocal:  false,
			durSec:   42.0,
			procSec:  1.5,
			tags:     []string{"reminder", "design"},
			daysAgo:  7,
			hoursAgo: 6,
		},
		{
			text:     "Ideen für den nächsten Blogpost: Vergleich zwischen Cloud-basierter und lokaler Spracherkennung. Vorteile der lokalen Verarbeitung: Datenschutz, keine Internetabhängigkeit, keine laufenden Kosten. Nachteile: Höherer Ressourcenverbrauch, initiale Einrichtung nötig.",
			title:    "Blog-Idee: Cloud vs. lokal",
			lang:     "de",
			model:    "whisper-base",
			isLocal:  true,
			durSec:   65.0,
			procSec:  3.4,
			tags:     []string{"draft", "blog"},
			project:  "proj-blog",
			daysAgo:  10,
			hoursAgo: 1,
		},
		{
			text:     "Meeting with the marketing team. Key decisions: launch campaign will focus on privacy-first messaging. Target audience is knowledge workers aged 25-45. Budget approved for Google Ads and LinkedIn sponsored content. Timeline: soft launch in two weeks, full campaign one month from now.",
			title:    "Marketing launch planning",
			lang:     "en",
			model:    "whisper-1",
			isLocal:  false,
			durSec:   275.0,
			procSec:  4.3,
			tags:     []string{"meeting", "marketing"},
			project:  "proj-meeting",
			daysAgo:  12,
			hoursAgo: 3,
		},
	}

	for i, e := range entries {
		ts := now.AddDate(0, 0, -e.daysAgo).Add(-time.Duration(e.hoursAgo) * time.Hour)
		id := fmt.Sprintf("demo-%04d", i+1)

		var cost float64
		if !e.isLocal && e.durSec > 0 {
			cost = (e.durSec / 60.0) * WhisperCostPerMinute
		}

		tagsJSON, _ := json.Marshal(e.tags)
		pinned := 0
		if e.pinned {
			pinned = 1
		}
		local := 0
		if e.isLocal {
			local = 1
		}

		db.Exec(`INSERT INTO history_entries 
			(id, text, title, timestamp, duration_sec, processing_duration_sec,
			 language, tags, pinned, source, model, is_local, cost_usd, project_id, archived)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'dictation', ?, ?, ?, ?, 0)`,
			id, e.text, e.title, ts.Format(time.RFC3339),
			e.durSec, e.procSec, e.lang,
			string(tagsJSON), pinned, e.model, local, cost, e.project,
		)

		// FTS index
		db.Exec(`INSERT INTO history_fts (rowid, title, text, tags) VALUES (
			(SELECT rowid FROM history_entries WHERE id = ?), ?, ?, ?)`,
			id, e.title, e.text, strings.Join(e.tags, " "),
		)
	}

	// --- Daily stats (for analytics page) ---
	statsData := []struct {
		daysAgo  int
		model    string
		isLocal  int
		count    int
		durSec   float64
		procSec  float64
		words    int
		costUSD  float64
		d15      int // dur_under_15s
		d1530    int // dur_15_30s
		d3060    int // dur_30_60s
		d13m     int // dur_1_3m
		d3m      int // dur_over_3m
	}{
		{0, "whisper-1", 0, 3, 520.0, 9.5, 285, 0.052, 0, 1, 0, 1, 1},
		{0, "whisper-base", 1, 2, 138.0, 5.3, 95, 0.0, 1, 0, 1, 0, 0},
		{1, "whisper-small", 1, 2, 95.0, 5.8, 72, 0.0, 0, 1, 1, 0, 0},
		{1, "qwen2.5-0.5b", 1, 1, 28.0, 1.9, 38, 0.0, 0, 1, 0, 0, 0},
		{2, "whisper-1", 0, 2, 290.0, 5.6, 165, 0.029, 0, 0, 0, 2, 0},
		{3, "whisper-1", 0, 1, 340.0, 5.1, 190, 0.034, 0, 0, 0, 0, 1},
		{3, "whisper-base", 1, 1, 18.0, 1.2, 22, 0.0, 1, 0, 0, 0, 0},
		{5, "whisper-small", 1, 1, 210.0, 8.5, 120, 0.0, 0, 0, 0, 0, 1},
		{6, "qwen3.5-0.8b", 1, 1, 88.0, 6.2, 50, 0.0, 0, 0, 1, 0, 0},
		{7, "whisper-1", 0, 1, 42.0, 1.5, 48, 0.004, 0, 0, 1, 0, 0},
		{10, "whisper-base", 1, 1, 65.0, 3.4, 42, 0.0, 0, 0, 0, 1, 0},
		{12, "whisper-1", 0, 1, 275.0, 4.3, 155, 0.028, 0, 0, 0, 0, 1},
	}

	for _, s := range statsData {
		date := now.AddDate(0, 0, -s.daysAgo).Format("2006-01-02")
		db.Exec(`INSERT OR REPLACE INTO daily_stats 
			(date, model, is_local, count, total_duration_sec, total_processing_sec,
			 total_words, total_cost_usd, dur_under_15s, dur_15_30s, dur_30_60s, dur_1_3m, dur_over_3m)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			date, s.model, s.isLocal, s.count,
			s.durSec, s.procSec, s.words, s.costUSD,
			s.d15, s.d1530, s.d3060, s.d13m, s.d3m,
		)
	}
}
