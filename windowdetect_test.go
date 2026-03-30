//go:build windows

package main

import "testing"

func TestResolveAppPresetForApp(t *testing.T) {
	mappings := map[string]string{
		"outlook.exe": "email",
		"slack.exe":   "casual",
		"word.exe":    "off",
	}

	tests := []struct {
		name     string
		appName  string
		want     string
		wantOkay bool
	}{
		{"exact match", "outlook.exe", "email", true},
		{"case insensitive", "SLACK.EXE", "casual", true},
		{"off is ignored", "word.exe", "", false},
		{"unknown app", "teams.exe", "", false},
		{"empty app", "", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := ResolveAppPresetForApp(tt.appName, mappings)
			if ok != tt.wantOkay {
				t.Fatalf("ResolveAppPresetForApp(%q) ok=%v, want %v", tt.appName, ok, tt.wantOkay)
			}
			if got != tt.want {
				t.Fatalf("ResolveAppPresetForApp(%q) = %q, want %q", tt.appName, got, tt.want)
			}
		})
	}
}
