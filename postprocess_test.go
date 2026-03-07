package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
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
		{"translate default", "translate", "", "", "en", nil, false, "Translate the following text to English"},
		{"translate german", "translate", "", "German", "en", nil, false, "Translate the following text to German"},
		{"custom prompt", "custom", "Fix spelling", "", "en", nil, false, "Fix spelling"},
		{"custom without prompt", "custom", "", "", "en", nil, true, ""},
		{"unknown preset", "nonexistent", "", "", "en", nil, true, ""},
		{"german suffix", "email", "", "", "de", nil, false, "Respond in German"},
		{"user template", "mypreset", "", "", "en", map[string]string{"mypreset": "Do stuff"}, false, "Do stuff"},
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
