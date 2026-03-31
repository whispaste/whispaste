package main

import (
	"strings"
	"testing"
)

func TestSanitizeMessage(t *testing.T) {
	redacted := "[REDACTED — contains sensitive data]"
	tests := []struct {
		input string
		want  string
	}{
		{"normal error text", "normal error text"},
		{"failed with sk-abc123xyz", redacted},
		{"gsk_token_here", redacted},
		{"api_key=SECRET", redacted},
		{"token=bar", redacted},
		{"password=hunter2", redacted},
		{"apiKey=xyz", redacted},
		{"Bearer eyJhbGci...", redacted},
		{"Authorization: Basic abc", redacted},
		{"error calling deepgram API", redacted},
		{"anthropic connection failed", redacted},
		{"gemini timeout", redacted},
	}
	for _, tc := range tests {
		got := sanitizeMessage(tc.input)
		if tc.want == redacted {
			if got != tc.want {
				t.Errorf("sanitizeMessage(%q) = %q, want %q", tc.input, got, tc.want)
			}
		} else if !strings.Contains(got, "normal error text") {
			t.Errorf("sanitizeMessage(%q) = %q, expected to contain original text", tc.input, got)
		}
	}
}

func TestSanitizePaths(t *testing.T) {
	t.Setenv("USERPROFILE", `C:\Users\testuser`)
	t.Setenv("USERNAME", "testuser")
	t.Setenv("APPDATA", `C:\Users\testuser\AppData\Roaming`)
	input := `C:\Users\testuser\AppData\Roaming\WhisPaste\file.db`
	got := sanitizePaths(input)
	if strings.Contains(got, "testuser") {
		t.Errorf("sanitizePaths did not redact username: %q", got)
	}
	if !strings.Contains(got, "<home>") && !strings.Contains(got, "<appdata>") {
		t.Errorf("sanitizePaths missing path placeholder: %q", got)
	}
}

func TestHashCrash(t *testing.T) {
	h1 := hashCrash("error A", "stack A")
	h2 := hashCrash("error A", "stack A")
	h3 := hashCrash("error B", "stack B")
	if h1 != h2 {
		t.Error("same input should produce same hash")
	}
	if h1 == h3 {
		t.Error("different input should produce different hash")
	}
	if len(h1) != 32 {
		t.Errorf("hash length = %d, want 32 hex chars", len(h1))
	}
}

func TestNewUUID(t *testing.T) {
	id := newUUID()
	if len(id) < 32 {
		t.Errorf("UUID too short: %q", id)
	}
	parts := strings.Split(id, "-")
	if len(parts) != 5 {
		t.Errorf("UUID should have 5 dash-separated parts, got %d: %q", len(parts), id)
	}
	id2 := newUUID()
	if id == id2 {
		t.Error("two UUIDs should not be identical")
	}
}

func TestBoolInt(t *testing.T) {
	if boolInt(true) != 1 {
		t.Error("boolInt(true) should be 1")
	}
	if boolInt(false) != 0 {
		t.Error("boolInt(false) should be 0")
	}
}

func TestTruncStr(t *testing.T) {
	if got := truncStr("hello", 10); got != "hello" {
		t.Errorf("short string: got %q", got)
	}
	if got := truncStr("hello world", 5); got != "hello…" {
		t.Errorf("truncated: got %q", got)
	}
}

func TestDeriveDeviceID(t *testing.T) {
	id := deriveDeviceID()
	if len(id) != 12 {
		t.Errorf("device ID length = %d, want 12", len(id))
	}
	id2 := deriveDeviceID()
	if id != id2 {
		t.Error("deriveDeviceID should be stable")
	}
}
