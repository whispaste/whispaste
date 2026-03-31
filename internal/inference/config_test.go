package inference

import (
	"runtime"
	"testing"
)

func TestOptimalThreads(t *testing.T) {
	// Should always return a value in [min, max]
	n := OptimalThreads(2, 8)
	if n < 2 || n > 8 {
		t.Errorf("OptimalThreads(2, 8) = %d, want [2, 8]", n)
	}

	// With very high min, should return min
	n = OptimalThreads(100, 200)
	if n < 100 {
		t.Errorf("OptimalThreads(100, 200) = %d, want >= 100", n)
	}
}

func TestSTTThreads(t *testing.T) {
	n := STTThreads()
	if n < 2 || n > 12 {
		t.Errorf("STTThreads() = %d, want [2, 12]", n)
	}
}

func TestLLMThreads(t *testing.T) {
	n := LLMThreads()
	if n < 2 || n > 8 {
		t.Errorf("LLMThreads() = %d, want [2, 8]", n)
	}
}

func TestProfileForPreset(t *testing.T) {
	tests := []struct {
		preset     string
		wantTemp   float64
		wantTokens int
	}{
		{"cleanup", 0.1, 1024},
		{"concise", 0.1, 1024},
		{"email", 0.1, 1024},
		{"bullets", 0.3, 2048},
		{"social", 0.7, 2048},
		{"casual", 0.7, 2048},
		{"notes", 0.0, 2048},
		{"unknown_preset", 0.3, 2048}, // defaults to Balanced
	}
	for _, tt := range tests {
		p := ProfileForPreset(tt.preset)
		if p.Temperature != tt.wantTemp {
			t.Errorf("ProfileForPreset(%q).Temperature = %v, want %v", tt.preset, p.Temperature, tt.wantTemp)
		}
		if p.MaxTokens != tt.wantTokens {
			t.Errorf("ProfileForPreset(%q).MaxTokens = %d, want %d", tt.preset, p.MaxTokens, tt.wantTokens)
		}
	}
}

func TestLLMCtxSize(t *testing.T) {
	// With explicit ctx size
	p := Profile{CtxSize: 4096}
	if got := LLMCtxSize(p); got != 4096 {
		t.Errorf("LLMCtxSize(4096) = %d, want 4096", got)
	}

	// With zero ctx size (use default)
	p = Profile{}
	if got := LLMCtxSize(p); got != 2048 {
		t.Errorf("LLMCtxSize(0) = %d, want 2048", got)
	}
}

func TestAutoTagProfile(t *testing.T) {
	p := AutoTagProfile()
	if p.Temperature != 0.1 {
		t.Errorf("AutoTagProfile().Temperature = %v, want 0.1", p.Temperature)
	}
	if p.MaxTokens != 100 {
		t.Errorf("AutoTagProfile().MaxTokens = %d, want 100", p.MaxTokens)
	}
}

func TestSTTTemperature(t *testing.T) {
	if got := STTTemperature(); got != 0.0 {
		t.Errorf("STTTemperature() = %v, want 0.0", got)
	}
}

// Verify threads scale with CPU count (basic sanity)
func TestThreadsScaleWithCPU(t *testing.T) {
	cpus := runtime.NumCPU()
	expected := cpus * 3 / 4
	if expected < 2 {
		expected = 2
	}
	if expected > 12 {
		expected = 12
	}
	if got := STTThreads(); got != expected {
		t.Errorf("STTThreads() = %d, want %d (for %d CPUs)", got, expected, cpus)
	}
}

func TestSTTThreadsCPUOnly(t *testing.T) {
	got := STTThreadsCPUOnly()
	want := runtime.NumCPU() - 1
	if want < 2 {
		want = 2
	}
	if want > 12 {
		want = 12
	}
	if got != want {
		t.Errorf("STTThreadsCPUOnly() = %d, want %d", got, want)
	}
}
