package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/whispaste/whispaste/internal/inference"
)

func TestMatchTemplate(t *testing.T) {
	metas := GetDefaultTemplateMetas()

	tests := []struct {
		name        string
		appName     string
		windowTitle string
		wantPreset  string
		wantFound   bool
	}{
		{"outlook matches email", "OUTLOOK.EXE", "Inbox - Outlook", "email", true},
		{"new outlook matches email via title", "olk.exe", "Inbox - Outlook (new)", "email", true},
		{"slack matches casual", "Slack", "general - Slack", "casual", true},
		{"vscode matches technical", "Code.exe", "main.go - Visual Studio Code", "technical", true},
		{"teams matches meeting", "Teams.exe", "Meeting - Microsoft Teams", "meeting", true},
		{"unknown app no match", "calc.exe", "Calculator", "", false},
		{"empty input no match", "", "", "", false},
		{"case insensitive", "outlook.exe", "inbox", "email", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			preset, found := MatchTemplate(tt.appName, tt.windowTitle, metas)
			if found != tt.wantFound {
				t.Errorf("MatchTemplate(%q, %q) found=%v, want %v", tt.appName, tt.windowTitle, found, tt.wantFound)
			}
			if found && preset != tt.wantPreset {
				t.Errorf("MatchTemplate(%q, %q) = %q, want %q", tt.appName, tt.windowTitle, preset, tt.wantPreset)
			}
		})
	}
}

func TestBuildSmartPrompt(t *testing.T) {
	tests := []struct {
		name         string
		preset       string
		customPrompt string
		targetLang   string
		appLang      string
		userTempl    map[string]string
		wantEmpty    bool
		wantContains string
	}{
		{"builtin cleanup", "cleanup", "", "", "en", nil, false, "Clean up"},
		{"translate default", "translate", "", "", "en", nil, false, "Translate the following text into English"},
		{"translate german", "translate", "", "German", "en", nil, false, "Translate the following text into German"},
		{"translate code", "translate", "", "de", "en", nil, false, "Translate the following text into German"},
		{"custom prompt", "custom", "Fix spelling", "", "en", nil, false, "TRANSFORMATION INSTRUCTIONS:\nFix spelling"},
		{"custom without prompt", "custom", "", "", "en", nil, true, ""},
		{"unknown preset", "nonexistent", "", "", "en", nil, true, ""},
		{"same language guardrail", "email", "", "", "de", nil, false, "The user's input is in German"},
		{"language hint used", "email", "", "", "fr", nil, false, "The user's input is in French"},
		{"email requires greeting", "email", "", "", "en", nil, false, "MUST include a suitable greeting"},
		{"user template", "mypreset", "", "", "en", map[string]string{"mypreset": "Do stuff"}, false, "TRANSFORMATION INSTRUCTIONS:\nDo stuff"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := buildSmartPrompt(tt.preset, tt.customPrompt, tt.targetLang, tt.appLang, tt.userTempl)
			if tt.wantEmpty && got != "" {
				t.Errorf("expected empty prompt, got %q", got)
			}
			if !tt.wantEmpty && got == "" {
				t.Error("expected non-empty prompt, got empty")
			}
			if tt.wantContains != "" && got != "" {
				if !strings.Contains(got, tt.wantContains) {
					t.Errorf("prompt %q does not contain %q", got, tt.wantContains)
				}
			}
		})
	}
}

func TestBuildBulkSmartPrompt(t *testing.T) {
	t.Run("translate uses configured target", func(t *testing.T) {
		got := buildBulkSmartPrompt("translate", "", "fr", "de", nil)
		if !strings.Contains(got, "Translate the following text into French") {
			t.Fatalf("expected French target in bulk prompt, got %q", got)
		}
	})

	t.Run("custom prompt keeps same-language guardrail", func(t *testing.T) {
		got := buildBulkSmartPrompt("custom", "Turn this into release notes.", "", "es", nil)
		if !strings.Contains(got, "The user's input is in Spanish") {
			t.Fatalf("expected Spanish language hint in bulk prompt, got %q", got)
		}
		if !strings.Contains(got, "Turn this into release notes.") {
			t.Fatalf("expected custom instruction in bulk prompt, got %q", got)
		}
	})
}

func TestStripThinkBlocks(t *testing.T) {
	tests := []struct {
		name, input, want string
	}{
		{"no think block", "Hello world", "Hello world"},
		{"single think block", "<think>internal reasoning</think>The answer is 42.", "The answer is 42."},
		{"multiline think", "<think>\nstep 1\nstep 2\n</think>\nClean result", "Clean result"},
		{"multiple blocks", "<think>a</think>Middle<think>b</think>End", "MiddleEnd"},
		{"only think block", "<think>reasoning only</think>", ""},
		{"nested tags", "<think>some <inner> tags</think>Result", "Result"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := stripThinkBlocks(tt.input)
			if got != tt.want {
				t.Errorf("stripThinkBlocks(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestPostProcessHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-key" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{"message": map[string]string{"content": "Cleaned text"}},
			},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	t.Run("successful postprocess", func(t *testing.T) {
		result, err := PostProcess("messy text", "cleanup", "", "", "test-key", srv.URL, "en", nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if result != "Cleaned text" {
			t.Errorf("got %q, want %q", result, "Cleaned text")
		}
	})

	t.Run("empty preset returns original", func(t *testing.T) {
		result, err := PostProcess("original text", "nonexistent", "", "", "test-key", srv.URL, "en", nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if result != "original text" {
			t.Errorf("got %q, want %q", result, "original text")
		}
	})

	t.Run("API error returns original text", func(t *testing.T) {
		result, err := PostProcess("text", "cleanup", "", "", "wrong-key", srv.URL, "en", nil)
		if err == nil {
			t.Fatal("expected error for wrong API key")
		}
		if result != "text" {
			t.Errorf("on error, should return original text, got %q", result)
		}
	})
}

func TestGetBuiltinPresets(t *testing.T) {
	presets := GetBuiltinPresets()
	required := []string{"cleanup", "email", "bullets", "formal", "concise", "aiprompt"}
	for _, name := range required {
		if _, ok := presets[name]; !ok {
			t.Errorf("missing builtin preset %q", name)
		}
	}
}

func TestLocalSmartMaxTokens(t *testing.T) {
	tests := []struct {
		name      string
		inputLen  int
		maxTokens int // profile MaxTokens
		want      int
	}{
		{"short text uses minimum", 100, 1024, 256},
		{"medium text scales", 1200, 1024, 428}, // 1200/4 + 128 = 428
		{"long text capped by profile", 8000, 1024, 1024},
		{"very short text uses minimum", 10, 2048, 256},
		{"proportional for 2000 chars", 2000, 2048, 628}, // 2000/4 + 128 = 628
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			profile := inference.Profile{MaxTokens: tt.maxTokens}
			got := localSmartMaxTokens(tt.inputLen, profile)
			if got != tt.want {
				t.Errorf("localSmartMaxTokens(%d, {MaxTokens:%d}) = %d, want %d",
					tt.inputLen, tt.maxTokens, got, tt.want)
			}
		})
	}
}

func TestPostProcessThinkBlockOnly(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{"message": map[string]string{"content": "<think>internal reasoning only</think>"}},
			},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	result, err := PostProcess("original text", "cleanup", "", "", "key", srv.URL, "en", nil)
	if err == nil {
		t.Fatal("expected error when response contains only think blocks")
	}
	if result != "original text" {
		t.Errorf("expected original text on think-block-only response, got %q", result)
	}
}

func TestPostProcessLocalMaxTokens(t *testing.T) {
	var capturedMaxTokens int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var reqBody map[string]interface{}
		json.NewDecoder(r.Body).Decode(&reqBody)
		if mt, ok := reqBody["max_tokens"].(float64); ok {
			capturedMaxTokens = int(mt)
		}
		resp := map[string]interface{}{
			"choices": []map[string]interface{}{
				{"message": map[string]string{"content": "Processed text"}},
			},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	// httptest.NewServer uses 127.0.0.1, so isLocalEndpoint returns true
	shortText := strings.Repeat("a", 400)
	_, err := PostProcess(shortText, "email", "", "", "key", srv.URL, "en", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// For 400 chars, localSmartMaxTokens = max(256, 400/4+128) = max(256, 228) = 256
	if capturedMaxTokens != 256 {
		t.Errorf("expected max_tokens=256 for local 400-char input, got %d", capturedMaxTokens)
	}
}

func TestNormalizeTranscription(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"no newlines", "Hello world", "Hello world"},
		{"single newline", "Hello\nworld", "Hello world"},
		{"multiple newlines", "Hello\nbeautiful\nworld", "Hello beautiful world"},
		{"crlf", "Hello\r\nworld", "Hello world"},
		{"mixed newlines", "Hello\r\nbeautiful\nworld", "Hello beautiful world"},
		{"leading trailing whitespace", "  Hello world  ", "Hello world"},
		{"multi spaces collapsed", "Hello   world", "Hello world"},
		{"newline creates double space", "Hello \n world", "Hello world"},
		{"empty string", "", ""},
		{"only newlines", "\n\n\n", ""},
		{"tabs collapsed", "Hello\t\tworld", "Hello world"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := normalizeTranscription(tt.in)
			if got != tt.want {
				t.Errorf("normalizeTranscription(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
