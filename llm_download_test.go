package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// helper to build mock asset lists
func llmAsset(name, url string) LLMReleaseAsset {
	return LLMReleaseAsset{Name: name, BrowserDownloadURL: url}
}

func TestMatchLLMAsset_ExactCUDAMatch(t *testing.T) {
	assets := []LLMReleaseAsset{
		llmAsset("llama-b5678-bin-win-cuda-cu12.2-x64.zip", "https://example.com/cuda12.zip"),
		llmAsset("llama-b5678-bin-win-vulkan-x64.zip", "https://example.com/vulkan.zip"),
		llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
	}
	got, err := matchLLMAsset(assets, "win-cuda")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/cuda12.zip" {
		t.Errorf("got %q, want cuda12 URL", got)
	}
}

func TestMatchLLMAsset_CUDA12PreferredOver13(t *testing.T) {
	// Test with CUDA 13 before CUDA 12 — must still prefer CUDA 12
	t.Run("cuda13_first", func(t *testing.T) {
		assets := []LLMReleaseAsset{
			llmAsset("llama-b5678-bin-win-cuda-cu13.0-x64.zip", "https://example.com/cuda13.zip"),
			llmAsset("llama-b5678-bin-win-cuda-cu12.4-x64.zip", "https://example.com/cuda12.zip"),
			llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
		}
		got, err := matchLLMAsset(assets, "win-cuda")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "https://example.com/cuda12.zip" {
			t.Errorf("got %q, want cuda12 URL (preferred over cuda13)", got)
		}
	})

	// Test with CUDA 12 before CUDA 13 — must still prefer CUDA 12
	t.Run("cuda12_first", func(t *testing.T) {
		assets := []LLMReleaseAsset{
			llmAsset("llama-b5678-bin-win-cuda-cu12.4-x64.zip", "https://example.com/cuda12.zip"),
			llmAsset("llama-b5678-bin-win-cuda-cu13.0-x64.zip", "https://example.com/cuda13.zip"),
			llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
		}
		got, err := matchLLMAsset(assets, "win-cuda")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got != "https://example.com/cuda12.zip" {
			t.Errorf("got %q, want cuda12 URL (preferred over cuda13)", got)
		}
	})
}

func TestMatchLLMAsset_VulkanFallback(t *testing.T) {
	assets := []LLMReleaseAsset{
		llmAsset("llama-b5678-bin-win-vulkan-x64.zip", "https://example.com/vulkan.zip"),
		llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
	}
	// Request CUDA, but none available → should fall back to Vulkan
	got, err := matchLLMAsset(assets, "win-cuda")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/vulkan.zip" {
		t.Errorf("got %q, want vulkan fallback URL", got)
	}
}

func TestMatchLLMAsset_CPUFallback(t *testing.T) {
	assets := []LLMReleaseAsset{
		llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
		llmAsset("cudart-llama-bin-win-cuda-cu12.2-x64.zip", "https://example.com/cudart.zip"), // should be excluded
	}
	// Request Vulkan, but not available → should fall back to CPU
	got, err := matchLLMAsset(assets, "win-vulkan-x64")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/cpu.zip" {
		t.Errorf("got %q, want cpu fallback URL", got)
	}
}

func TestMatchLLMAsset_NoMatch(t *testing.T) {
	tests := []struct {
		name   string
		assets []LLMReleaseAsset
		key    string
	}{
		{"empty list", nil, "win-cuda"},
		{"no matching assets", []LLMReleaseAsset{
			llmAsset("llama-b5678-bin-linux-x64.tar.gz", "https://example.com/linux.tar.gz"),
		}, "win-cpu-x64"},
		{"only cudart prefix", []LLMReleaseAsset{
			llmAsset("cudart-llama-bin-win-cuda-cu12.2-x64.zip", "https://example.com/cudart.zip"),
		}, "win-cuda"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := matchLLMAsset(tt.assets, tt.key)
			if err == nil {
				t.Fatal("expected error, got nil")
			}
			if !strings.Contains(err.Error(), "no matching asset") {
				t.Errorf("unexpected error message: %v", err)
			}
		})
	}
}

func TestMatchLLMAsset_PreferGPUOverCPU(t *testing.T) {
	assets := []LLMReleaseAsset{
		llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
		llmAsset("llama-b5678-bin-win-cuda-cu12.2-x64.zip", "https://example.com/cuda12.zip"),
	}
	got, err := matchLLMAsset(assets, "win-cuda")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/cuda12.zip" {
		t.Errorf("got %q, want cuda12 GPU URL (not CPU)", got)
	}
}

func TestMatchLLMAsset_CPUKeySelectsCPU(t *testing.T) {
	assets := []LLMReleaseAsset{
		llmAsset("llama-b5678-bin-win-cuda-cu12.2-x64.zip", "https://example.com/cuda12.zip"),
		llmAsset("llama-b5678-bin-win-vulkan-x64.zip", "https://example.com/vulkan.zip"),
		llmAsset("llama-b5678-bin-win-cpu-x64.zip", "https://example.com/cpu.zip"),
	}
	got, err := matchLLMAsset(assets, "win-cpu-x64")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "https://example.com/cpu.zip" {
		t.Errorf("got %q, want cpu URL when explicitly requesting CPU", got)
	}
}

func TestLLMServerAssetMarkers(t *testing.T) {
	dir := t.TempDir()
	if got := llmServerAssetKey(dir); got != "" {
		t.Fatalf("llmServerAssetKey(empty) = %q, want empty", got)
	}
	if got := llmServerRequestedKey(dir); got != "" {
		t.Fatalf("llmServerRequestedKey(empty) = %q, want empty", got)
	}

	writeLLMServerAssetKey(dir, "win-vulkan-x64")
	writeLLMServerRequestedKey(dir, "win-cuda")

	if got := llmServerAssetKey(dir); got != "win-vulkan-x64" {
		t.Fatalf("llmServerAssetKey() = %q, want %q", got, "win-vulkan-x64")
	}
	if got := llmServerRequestedKey(dir); got != "win-cuda" {
		t.Fatalf("llmServerRequestedKey() = %q, want %q", got, "win-cuda")
	}
}

func TestLLMServerNeedsRefresh(t *testing.T) {
	appData := t.TempDir()
	t.Setenv("APPDATA", appData)
	dir := filepath.Join(appData, AppName, "models", "llm")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatalf("mkdir llm dir: %v", err)
	}

	serverPath := filepath.Join(dir, "llama-server.exe")
	if err := os.WriteFile(serverPath, []byte("stub"), 0600); err != nil {
		t.Fatalf("write server: %v", err)
	}

	// No markers → needs refresh
	if !llmServerNeedsRefresh(dir, "disabled") {
		t.Fatal("missing markers should trigger refresh")
	}

	// Write matching markers
	wantKey := llmAssetKey("disabled")
	writeLLMServerAssetKey(dir, wantKey)
	writeLLMServerRequestedKey(dir, wantKey)

	if llmServerNeedsRefresh(dir, "disabled") {
		t.Fatal("matching markers should not trigger refresh")
	}

	// Change GPU mode → mismatched requested key → needs refresh
	writeLLMServerRequestedKey(dir, "win-cuda")
	if !llmServerNeedsRefresh(dir, "disabled") {
		t.Fatal("mismatched requested key should trigger refresh")
	}
}
