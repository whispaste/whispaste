package main

import (
	"testing"
)

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

func TestTranscribeLocal_TooShort(t *testing.T) {
	_, err := TranscribeLocal([]byte{0x00}, 16000, "en", "whisper-base")
	if err == nil {
		t.Error("expected error for too-short audio")
	}
}
