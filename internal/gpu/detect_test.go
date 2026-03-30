package gpu

import (
	"testing"
)

func TestShouldUseGPU(t *testing.T) {
	// "disabled" should always return false regardless of hardware
	if ShouldUseGPU("disabled", 0) {
		t.Error("ShouldUseGPU(disabled) should be false")
	}

	// "enabled" should always return true
	if !ShouldUseGPU("enabled", 0) {
		t.Error("ShouldUseGPU(enabled) should be true")
	}
}

func TestRecommendAssetKeys(t *testing.T) {
	// With GPU disabled, should return CPU keys
	if got := RecommendSTTAssetKey("disabled"); got != "bin-x64" {
		t.Errorf("RecommendSTTAssetKey(disabled) = %q, want 'bin-x64'", got)
	}
	if got := RecommendLLMAssetKey("disabled"); got != "win-cpu-x64" {
		t.Errorf("RecommendLLMAssetKey(disabled) = %q, want 'win-cpu-x64'", got)
	}

	// With GPU enabled, should return CUDA keys
	if got := RecommendSTTAssetKey("enabled"); got != "cuda" {
		t.Errorf("RecommendSTTAssetKey(enabled) = %q, want 'cuda'", got)
	}
	if got := RecommendLLMAssetKey("enabled"); got != "win-cuda-cu12.2-x64" {
		t.Errorf("RecommendLLMAssetKey(enabled) = %q, want 'win-cuda-cu12.2-x64'", got)
	}
}

func TestInfoHasSufficientVRAM(t *testing.T) {
	noGPU := Info{Available: false}
	if noGPU.HasSufficientVRAM(0) {
		t.Error("no GPU should not have sufficient VRAM")
	}

	smallGPU := Info{Available: true, VRAMMBytes: 1024}
	if smallGPU.HasSufficientVRAM(2048) {
		t.Error("1GB GPU should not satisfy 2GB requirement")
	}
	if !smallGPU.HasSufficientVRAM(1024) {
		t.Error("1GB GPU should satisfy 1GB requirement")
	}

	bigGPU := Info{Available: true, VRAMMBytes: 8192}
	if !bigGPU.HasSufficientVRAM(4096) {
		t.Error("8GB GPU should satisfy 4GB requirement")
	}
}
