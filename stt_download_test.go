package main

import (
	"strings"
	"testing"
)

// helper to build a ReleaseAsset from a filename.
func asset(name string) ReleaseAsset {
	return ReleaseAsset{
		Name:               name,
		BrowserDownloadURL: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.7.3/" + name,
	}
}

// Realistic asset set mirroring a typical whisper.cpp release.
var realisticAssets = []ReleaseAsset{
	asset("whisper-bin-x64.zip"),
	asset("whisper-blas-bin-x64.zip"),
	asset("whisper-cublas-12.2.0-bin-x64.zip"),
	asset("whisper-cublas-11.8.0-bin-x64.zip"),
	asset("whisper-bin-Win32.zip"),
	asset("whisper-blas-bin-Win32.zip"),
	asset("Source code.tar.gz"),
}

func TestMatchSTTAsset(t *testing.T) {
	tests := []struct {
		name      string
		assets    []ReleaseAsset
		assetKey  string
		wantURL   string // substring that must appear in the returned URL
		wantError bool
	}{
		{
			name:     "ExactMatch",
			assets:   realisticAssets,
			assetKey: "cublas-12.2",
			wantURL:  "whisper-cublas-12.2.0-bin-x64.zip",
		},
		{
			name: "BlasFallback",
			assets: []ReleaseAsset{
				asset("whisper-blas-bin-x64.zip"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey: "cublas-12.2",
			wantURL:  "whisper-blas-bin-x64.zip",
		},
		{
			name: "GenericFallback",
			assets: []ReleaseAsset{
				asset("whisper-bin-x64.zip"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey: "cublas-12.2",
			wantURL:  "whisper-bin-x64.zip",
		},
		{
			name:     "NoCUDAFallback",
			assets:   realisticAssets,
			assetKey: "blas-bin-x64",
			wantURL:  "whisper-blas-bin-x64.zip",
		},
		{
			name:      "NoMatch_EmptyList",
			assets:    []ReleaseAsset{},
			assetKey:  "blas-bin-x64",
			wantError: true,
		},
		{
			name: "NoMatch_OnlyUnrelated",
			assets: []ReleaseAsset{
				asset("Source code.tar.gz"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey:  "cublas-12.2",
			wantError: true,
		},
		{
			name:     "PreferExactOverFallback",
			assets:   realisticAssets,
			assetKey: "cublas-12.2",
			wantURL:  "whisper-cublas-12.2.0-bin-x64.zip",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := matchSTTAsset(tt.assets, tt.assetKey)
			if tt.wantError {
				if err == nil {
					t.Fatalf("expected error, got URL %q", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !strings.Contains(got, tt.wantURL) {
				t.Errorf("got %q, want URL containing %q", got, tt.wantURL)
			}
		})
	}
}
