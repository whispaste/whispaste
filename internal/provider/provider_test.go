package provider

import (
	"testing"
)

func TestNewCloudSTT(t *testing.T) {
	tests := []struct {
		id      string
		wantErr bool
		name    string
	}{
		{"openai", false, "openai"},
		{"groq", false, "groq"},
		{"deepgram", false, "deepgram"},
		{"", false, "openai"}, // default
		{"unknown", true, ""},
	}
	for _, tt := range tests {
		p, err := NewCloudSTT(tt.id, "test-key")
		if tt.wantErr {
			if err == nil {
				t.Errorf("NewCloudSTT(%q) expected error", tt.id)
			}
			continue
		}
		if err != nil {
			t.Errorf("NewCloudSTT(%q) unexpected error: %v", tt.id, err)
			continue
		}
		if p.Name() != tt.name {
			t.Errorf("NewCloudSTT(%q).Name() = %q, want %q", tt.id, p.Name(), tt.name)
		}
	}
}

func TestNewCloudLLM(t *testing.T) {
	tests := []struct {
		id      string
		wantErr bool
		name    string
	}{
		{"openai", false, "openai"},
		{"anthropic", false, "anthropic"},
		{"gemini", false, "gemini"},
		{"groq", false, "groq"},
		{"", false, "openai"},     // default
		{"cloud", false, "openai"}, // legacy "cloud" maps to openai
		{"unknown", true, ""},
	}
	for _, tt := range tests {
		p, err := NewCloudLLM(tt.id, "test-key")
		if tt.wantErr {
			if err == nil {
				t.Errorf("NewCloudLLM(%q) expected error", tt.id)
			}
			continue
		}
		if err != nil {
			t.Errorf("NewCloudLLM(%q) unexpected error: %v", tt.id, err)
			continue
		}
		if p.Name() != tt.name {
			t.Errorf("NewCloudLLM(%q).Name() = %q, want %q", tt.id, p.Name(), tt.name)
		}
	}
}

func TestNewCustomProviders(t *testing.T) {
	stt := NewCustomSTT("https://example.com/v1/stt", "key", "model")
	if stt.Name() != "custom" {
		t.Errorf("CustomSTT.Name() = %q, want 'custom'", stt.Name())
	}

	llm := NewCustomLLM("https://example.com/v1/chat", "key", "model")
	if llm.Name() != "custom" {
		t.Errorf("CustomLLM.Name() = %q, want 'custom'", llm.Name())
	}
}

func TestCloudSTTProviders(t *testing.T) {
	if len(CloudSTTProviders) != 3 {
		t.Errorf("CloudSTTProviders has %d entries, want 3", len(CloudSTTProviders))
	}
	ids := map[string]bool{}
	for _, p := range CloudSTTProviders {
		if ids[p.ID] {
			t.Errorf("duplicate STT provider ID: %s", p.ID)
		}
		ids[p.ID] = true
		if len(p.Models) == 0 {
			t.Errorf("STT provider %s has no models", p.ID)
		}
	}
}

func TestCloudLLMProviders(t *testing.T) {
	if len(CloudLLMProviders) != 4 {
		t.Errorf("CloudLLMProviders has %d entries, want 4", len(CloudLLMProviders))
	}
	ids := map[string]bool{}
	for _, p := range CloudLLMProviders {
		if ids[p.ID] {
			t.Errorf("duplicate LLM provider ID: %s", p.ID)
		}
		ids[p.ID] = true
		if len(p.Models) == 0 {
			t.Errorf("LLM provider %s has no models", p.ID)
		}
	}
}

func TestDefaultLLMOptions(t *testing.T) {
	opts := DefaultLLMOptions()
	if opts.Temperature != 0.3 {
		t.Errorf("DefaultLLMOptions().Temperature = %v, want 0.3", opts.Temperature)
	}
	if opts.MaxTokens != 2048 {
		t.Errorf("DefaultLLMOptions().MaxTokens = %d, want 2048", opts.MaxTokens)
	}
	if opts.TopP != 0.95 {
		t.Errorf("DefaultLLMOptions().TopP = %v, want 0.95", opts.TopP)
	}
}

func TestNormalizeText(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"hello world", "hello world"},
		{"  hello  world  ", "hello world"},
		{"hello\nworld", "hello world"},
		{"hello\r\nworld", "hello world"},
		{"  ", ""},
	}
	for _, tt := range tests {
		got := normalizeText(tt.input)
		if got != tt.want {
			t.Errorf("normalizeText(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestParseAPIError(t *testing.T) {
	err := parseAPIError("test", 401, nil)
	if err == nil || !contains(err.Error(), "authentication") {
		t.Errorf("parseAPIError(401) = %v, want authentication error", err)
	}

	err = parseAPIError("test", 429, nil)
	if err == nil || !contains(err.Error(), "rate limit") {
		t.Errorf("parseAPIError(429) = %v, want rate limit error", err)
	}

	err = parseAPIError("test", 500, nil)
	if err == nil || !contains(err.Error(), "server error") {
		t.Errorf("parseAPIError(500) = %v, want server error", err)
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && containsStr(s, sub)
}

func containsStr(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
