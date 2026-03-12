package main

import "testing"

func TestClassifyAudioInputHealth(t *testing.T) {
	tests := []struct {
		name    string
		peak    float32
		average float32
		reads   uint32
		want    string
	}{
		{name: "checking until enough samples", peak: 0.20, average: 0.08, reads: 2, want: "checking"},
		{name: "silent signal", peak: 0.01, average: 0.005, reads: 12, want: "silent"},
		{name: "quiet signal", peak: 0.08, average: 0.03, reads: 12, want: "quiet"},
		{name: "healthy signal", peak: 0.34, average: 0.14, reads: 12, want: "good"},
		{name: "too hot", peak: 0.96, average: 0.40, reads: 12, want: "hot"},
	}

	for _, tt := range tests {
		if got := classifyAudioInputHealth(tt.peak, tt.average, tt.reads); got != tt.want {
			t.Errorf("%s: classifyAudioInputHealth(%0.3f, %0.3f, %d) = %q, want %q", tt.name, tt.peak, tt.average, tt.reads, got, tt.want)
		}
	}
}
