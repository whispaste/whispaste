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
		{`request failed: {"api_key":"SECRET"}`, redacted},
		{"error calling deepgram API", "error calling deepgram API"},
		{"anthropic connection failed", "anthropic connection failed"},
		{"gemini timeout", "gemini timeout"},
	}
	for _, tc := range tests {
		got := sanitizeMessage(tc.input)
		if tc.want == redacted {
			if got != tc.want {
				t.Errorf("sanitizeMessage(%q) = %q, want %q", tc.input, got, tc.want)
			}
		} else if got != tc.want {
			t.Errorf("sanitizeMessage(%q) = %q, want %q", tc.input, got, tc.want)
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

func TestBuildCrashConfigSnapshotIncludesDebugContextWithoutSecrets(t *testing.T) {
	cfg := DefaultConfig()
	cfg.UseLocalSTT = false
	cfg.CloudSTTProvider = "deepgram"
	cfg.Model = "nova-3"
	cfg.Language = "de"
	cfg.InputDevice = "Microphone (USB Audio)"
	cfg.InputGain = 1.25
	cfg.UseVAD = true
	cfg.VADSensitivity = 0.7
	cfg.TrimSilence = true
	cfg.SmartMode = true
	cfg.SmartModeProvider = "cloud"
	cfg.CloudLLMProvider = "anthropic"
	cfg.CloudLLMModel = "claude-3-7-sonnet"
	cfg.SmartModePreset = "cleanup"
	cfg.SmartModeTarget = "en"
	cfg.ActiveProfile = "team-notes"
	cfg.UpdateChannel = "beta"
	cfg.GPUAcceleration = "auto"
	cfg.APIKey = "sk-secret-123"
	cfg.DeepgramAPIKey = "dg-secret-456"

	got := buildCrashConfigSnapshot(cfg)

	for _, want := range []string{
		"profile=team-notes",
		"provider=deepgram",
		"model=nova-3",
		"lang=de",
		"provider=anthropic",
		"model=claude-3-7-sonnet",
		"vad=true(0.70)",
		"device:Microphone (USB Audio)",
		"updates=beta",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("snapshot missing %q: %s", want, got)
		}
	}
	for _, secret := range []string{"sk-secret-123", "dg-secret-456"} {
		if strings.Contains(got, secret) {
			t.Fatalf("snapshot leaked secret %q: %s", secret, got)
		}
	}
}

func TestBuildEmbedIncludesVersionBuildAndRuntimeConfig(t *testing.T) {
	cr := &CrashReporter{}
	report := &crashReport{
		ID:             "12345678-abcd-ef01-2345-6789abcdef01",
		Timestamp:      1711893600,
		Type:           "error",
		Severity:       "error",
		Message:        "test failure",
		StackTrace:     "main.test\n\tfile.go:10",
		AppVersion:     "1.2.3",
		BuildCommit:    "abcdef1234567890",
		GoVersion:      "go1.26.0",
		OS:             "windows",
		Arch:           "amd64",
		DeviceID:       "device123",
		GPU:            "auto",
		ConfigSnapshot: "profile=default\nstt=cloud | provider=openai",
	}

	embed := cr.buildEmbed(report)
	fields, ok := embed["fields"].([]map[string]interface{})
	if !ok {
		t.Fatalf("embed fields has unexpected type: %T", embed["fields"])
	}

	values := map[string]string{}
	for _, field := range fields {
		name, _ := field["name"].(string)
		value, _ := field["value"].(string)
		values[name] = value
	}

	if values["Version"] != "1.2.3" {
		t.Fatalf("Version field = %q, want 1.2.3", values["Version"])
	}
	if values["Build"] != "abcdef123456…" {
		t.Fatalf("Build field = %q, want truncated commit", values["Build"])
	}
	if !strings.Contains(values["Runtime Config"], "provider=openai") {
		t.Fatalf("Runtime Config field missing snapshot: %q", values["Runtime Config"])
	}
}
