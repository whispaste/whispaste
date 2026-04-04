//go:build windows

package main

import "testing"

func TestResolveStreamingPreviewModelWith(t *testing.T) {
	tests := []struct {
		name         string
		selected     string
		available    map[string]bool
		wantRuntime  string
		wantDownload string
		wantReady    bool
		wantSelected bool
	}{
		{
			name:         "uses selected fast model when available",
			selected:     "whisper-base",
			available:    map[string]bool{"whisper-base": true},
			wantRuntime:  "whisper-base",
			wantDownload: "whisper-base",
			wantReady:    true,
			wantSelected: true,
		},
		{
			name:         "prefers downloaded base for large model",
			selected:     "whisper-large-v3",
			available:    map[string]bool{"whisper-base": true},
			wantRuntime:  "whisper-base",
			wantDownload: "whisper-base",
			wantReady:    true,
			wantSelected: false,
		},
		{
			name:         "falls back to tiny when base is missing",
			selected:     "whisper-large-v3-turbo",
			available:    map[string]bool{"whisper-tiny": true},
			wantRuntime:  "whisper-tiny",
			wantDownload: "whisper-tiny",
			wantReady:    true,
			wantSelected: false,
		},
		{
			name:         "requests base download when nothing fast is present",
			selected:     "whisper-large-v3",
			available:    map[string]bool{},
			wantRuntime:  "whisper-base",
			wantDownload: "whisper-base",
			wantReady:    false,
			wantSelected: false,
		},
		{
			name:         "keeps selected tiny as download target",
			selected:     "whisper-tiny",
			available:    map[string]bool{},
			wantRuntime:  "whisper-tiny",
			wantDownload: "whisper-tiny",
			wantReady:    false,
			wantSelected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			state := resolveStreamingPreviewModelWith(tc.selected, func(modelID string) bool {
				return tc.available[modelID]
			})
			if state.RuntimeModelID != tc.wantRuntime {
				t.Fatalf("RuntimeModelID = %q, want %q", state.RuntimeModelID, tc.wantRuntime)
			}
			if state.DownloadModelID != tc.wantDownload {
				t.Fatalf("DownloadModelID = %q, want %q", state.DownloadModelID, tc.wantDownload)
			}
			if state.Ready != tc.wantReady {
				t.Fatalf("Ready = %v, want %v", state.Ready, tc.wantReady)
			}
			if state.UsesSelected != tc.wantSelected {
				t.Fatalf("UsesSelected = %v, want %v", state.UsesSelected, tc.wantSelected)
			}
		})
	}
}

func TestCalculateStreamingPreviewPosition(t *testing.T) {
	tests := []struct {
		name               string
		overlayX, overlayY int
		overlayW, overlayH int
		previewW, previewH int
		minX, minY         int
		maxX, maxY         int
		wantY              int
	}{
		{
			name:     "prefers below when overlay is near top",
			overlayX: 200, overlayY: 24, overlayW: 490, overlayH: 80,
			previewW: 180, previewH: 36,
			minX: 0, minY: 0, maxX: 1920, maxY: 1080,
			wantY: 24 + 80 + _STW_GAP,
		},
		{
			name:     "prefers above when overlay is near bottom",
			overlayX: 200, overlayY: 920, overlayW: 490, overlayH: 80,
			previewW: 180, previewH: 36,
			minX: 0, minY: 0, maxX: 1920, maxY: 1080,
			wantY: 920 - 36 - _STW_GAP,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, gotY := calculateStreamingPreviewPosition(tc.overlayX, tc.overlayY, tc.overlayW, tc.overlayH, tc.previewW, tc.previewH, tc.minX, tc.minY, tc.maxX, tc.maxY)
			if gotY != tc.wantY {
				t.Fatalf("y = %d, want %d", gotY, tc.wantY)
			}
		})
	}
}
