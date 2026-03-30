package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/whispaste/whispaste/internal/gpu"
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

var whispasteAssets = []ReleaseAsset{
	asset("whisper-server-vulkan-x64.zip"),
	asset("whisper-server-cuda12-x64.zip"),
	asset("whisper-server-cpu-x64.zip"),
}

func TestMatchSTTAsset(t *testing.T) {
	tests := []struct {
		name      string
		repo      string
		assets    []ReleaseAsset
		assetKey  string
		wantURL   string // substring that must appear in the returned URL
		wantError bool
	}{
		{
			name:     "ExactMatchUpstream",
			repo:     sttServerRepoUpstream,
			assets:   realisticAssets,
			assetKey: "cublas-12.2",
			wantURL:  "whisper-cublas-12.2.0-bin-x64.zip",
		},
		{
			name: "BlasFallbackUpstream",
			repo: sttServerRepoUpstream,
			assets: []ReleaseAsset{
				asset("whisper-blas-bin-x64.zip"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey: "cublas-12.2",
			wantURL:  "whisper-blas-bin-x64.zip",
		},
		{
			name: "GenericFallbackUpstream",
			repo: sttServerRepoUpstream,
			assets: []ReleaseAsset{
				asset("whisper-bin-x64.zip"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey: "cublas-12.2",
			wantURL:  "whisper-bin-x64.zip",
		},
		{
			name:     "NoCUDAFallbackUpstream",
			repo:     sttServerRepoUpstream,
			assets:   realisticAssets,
			assetKey: "blas-bin-x64",
			wantURL:  "whisper-blas-bin-x64.zip",
		},
		{
			name:      "NoMatchEmptyListUpstream",
			repo:      sttServerRepoUpstream,
			assets:    []ReleaseAsset{},
			assetKey:  "blas-bin-x64",
			wantError: true,
		},
		{
			name: "NoMatchOnlyUnrelatedUpstream",
			repo: sttServerRepoUpstream,
			assets: []ReleaseAsset{
				asset("Source code.tar.gz"),
				asset("whisper-bin-Win32.zip"),
			},
			assetKey:  "cublas-12.2",
			wantError: true,
		},
		{
			name:     "PreferExactOverFallbackUpstream",
			repo:     sttServerRepoUpstream,
			assets:   realisticAssets,
			assetKey: "cublas-12.2",
			wantURL:  "whisper-cublas-12.2.0-bin-x64.zip",
		},
		{
			name:     "WhisPasteVulkanAsset",
			repo:     sttServerRepoWhisPaste,
			assets:   whispasteAssets,
			assetKey: "whisper-server-vulkan-x64",
			wantURL:  "whisper-server-vulkan-x64.zip",
		},
		{
			name:      "WhisPasteMissingAsset",
			repo:      sttServerRepoWhisPaste,
			assets:    whispasteAssets,
			assetKey:  "whisper-server-metal-x64",
			wantError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := matchSTTAsset(tt.assets, tt.repo, tt.assetKey)
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

func TestSTTAssetCandidates(t *testing.T) {
	origDetect := gpuDetect
	origShouldUse := gpuShouldUse
	t.Cleanup(func() {
		gpuDetect = origDetect
		gpuShouldUse = origShouldUse
	})

	tests := []struct {
		name      string
		mode      string
		detect    gpu.Info
		useGPU    bool
		wantRepos []string
		wantKeys  []string
	}{
		{
			name:      "NVIDIAEnabledTriesWhisPasteThenUpstream",
			mode:      "enabled",
			detect:    gpu.Info{Available: true, Vendor: gpu.VendorNVIDIA},
			useGPU:    true,
			wantRepos: []string{sttServerRepoWhisPaste, sttServerRepoUpstream, sttServerRepoWhisPaste, sttServerRepoUpstream},
			wantKeys:  []string{"whisper-server-cuda12-x64", "cublas-12", "whisper-server-cpu-x64", "blas-bin-x64"},
		},
		{
			name:      "AMDAutoPrefersVulkanThenCPUFallback",
			mode:      "auto",
			detect:    gpu.Info{Available: true, Vendor: gpu.VendorAMD},
			useGPU:    true,
			wantRepos: []string{sttServerRepoWhisPaste, sttServerRepoWhisPaste, sttServerRepoUpstream},
			wantKeys:  []string{"whisper-server-vulkan-x64", "whisper-server-cpu-x64", "blas-bin-x64"},
		},
		{
			name:      "DisabledUsesCPUOnly",
			mode:      "disabled",
			detect:    gpu.Info{Available: true, Vendor: gpu.VendorNVIDIA},
			useGPU:    false,
			wantRepos: []string{sttServerRepoWhisPaste, sttServerRepoUpstream},
			wantKeys:  []string{"whisper-server-cpu-x64", "blas-bin-x64"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gpuDetect = func() gpu.Info { return tt.detect }
			gpuShouldUse = func(mode string, minVRAMMB int) bool { return tt.useGPU }

			got := sttAssetCandidates(tt.mode)
			if len(got) != len(tt.wantRepos) {
				t.Fatalf("len(candidates) = %d, want %d", len(got), len(tt.wantRepos))
			}
			for i, candidate := range got {
				if candidate.Repo != tt.wantRepos[i] {
					t.Errorf("candidate[%d].Repo = %q, want %q", i, candidate.Repo, tt.wantRepos[i])
				}
				if candidate.AssetKey != tt.wantKeys[i] {
					t.Errorf("candidate[%d].AssetKey = %q, want %q", i, candidate.AssetKey, tt.wantKeys[i])
				}
			}
		})
	}
}

func TestResolveSTTServerURLFallsBackAcrossRepos(t *testing.T) {
	origFetch := fetchSTTReleaseAssets
	origDetect := gpuDetect
	origShouldUse := gpuShouldUse
	t.Cleanup(func() {
		fetchSTTReleaseAssets = origFetch
		gpuDetect = origDetect
		gpuShouldUse = origShouldUse
	})

	gpuDetect = func() gpu.Info { return gpu.Info{Available: true, Vendor: gpu.VendorAMD} }
	gpuShouldUse = func(mode string, minVRAMMB int) bool { return true }

	fetchSTTReleaseAssets = func(repo string) ([]ReleaseAsset, error) {
		switch repo {
		case sttServerRepoWhisPaste:
			return nil, errors.New("repo unavailable")
		case sttServerRepoUpstream:
			return realisticAssets, nil
		default:
			t.Fatalf("unexpected repo %q", repo)
			return nil, nil
		}
	}

	got, err := resolveSTTServerURL("auto")
	if err != nil {
		t.Fatalf("resolveSTTServerURL() error = %v", err)
	}
	if !strings.Contains(got, "whisper-blas-bin-x64.zip") {
		t.Errorf("resolveSTTServerURL() = %q, want upstream CPU fallback", got)
	}
}
