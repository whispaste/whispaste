package main

import (
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
