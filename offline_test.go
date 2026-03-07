package main

import (
	"math"
	"testing"
)

func TestNumThreads(t *testing.T) {
	n := numThreads()
	if n < 1 {
		t.Errorf("numThreads() = %d, must be >= 1", n)
	}
	if n > 4 {
		t.Errorf("numThreads() = %d, must be capped at 4", n)
	}
}

func TestNormalizeLanguage(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"auto", ""},
		{"", ""},
		{"en", "en"},
		{"de", "de"},
		{"ja", "ja"},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := normalizeLanguage(tt.input)
			if got != tt.want {
				t.Errorf("normalizeLanguage(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestPcmToFloat32(t *testing.T) {
	t.Run("known samples", func(t *testing.T) {
		// Silence: two bytes of zero
		pcm := []byte{0x00, 0x00}
		samples := pcmToFloat32(pcm)
		if len(samples) != 1 {
			t.Fatalf("expected 1 sample, got %d", len(samples))
		}
		if samples[0] != 0.0 {
			t.Errorf("silence sample = %f, want 0.0", samples[0])
		}
	})

	t.Run("max positive", func(t *testing.T) {
		// int16 max = 32767 = 0xFF7F little-endian
		pcm := []byte{0xFF, 0x7F}
		samples := pcmToFloat32(pcm)
		expected := float32(32767) / 32768.0
		if math.Abs(float64(samples[0]-expected)) > 0.0001 {
			t.Errorf("max positive sample = %f, want %f", samples[0], expected)
		}
	})

	t.Run("max negative", func(t *testing.T) {
		// int16 min = -32768 = 0x0080 little-endian
		pcm := []byte{0x00, 0x80}
		samples := pcmToFloat32(pcm)
		expected := float32(-32768) / 32768.0
		if math.Abs(float64(samples[0]-expected)) > 0.0001 {
			t.Errorf("max negative sample = %f, want %f", samples[0], expected)
		}
	})

	t.Run("multiple samples", func(t *testing.T) {
		pcm := []byte{0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80}
		samples := pcmToFloat32(pcm)
		if len(samples) != 3 {
			t.Fatalf("expected 3 samples, got %d", len(samples))
		}
	})

	t.Run("empty input", func(t *testing.T) {
		samples := pcmToFloat32([]byte{})
		if len(samples) != 0 {
			t.Errorf("expected 0 samples for empty input, got %d", len(samples))
		}
	})
}
