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
	// With GPU disabled, should return CPU keys (OpenBLAS for STT, CPU for LLM)
	if got := RecommendSTTAssetKey("disabled"); got != "blas-bin-x64" {
		t.Errorf("RecommendSTTAssetKey(disabled) = %q, want 'blas-bin-x64'", got)
	}
	if got := RecommendLLMAssetKey("disabled"); got != "win-cpu-x64" {
		t.Errorf("RecommendLLMAssetKey(disabled) = %q, want 'win-cpu-x64'", got)
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

func TestVendorFromName(t *testing.T) {
	tests := []struct {
		name   string
		vendor Vendor
	}{
		{"NVIDIA GeForce RTX 4090", VendorNVIDIA},
		{"NVIDIA GeForce GTX 1660 Ti", VendorNVIDIA},
		{"AMD Radeon RX 7900 XTX", VendorAMD},
		{"AMD Radeon(TM) Graphics", VendorAMD},
		{"Radeon RX 580", VendorAMD},
		{"Intel(R) UHD Graphics 770", VendorIntel},
		{"Intel(R) Iris(R) Xe Graphics", VendorIntel},
		{"Intel(R) Arc(TM) A770", VendorIntel},
		{"Intel(R) Arc A750", VendorIntel},
		{"Microsoft Basic Display Adapter", VendorUnknown},
	}

	for _, tc := range tests {
		got := vendorFromName(tc.name)
		if got != tc.vendor {
			t.Errorf("vendorFromName(%q) = %q, want %q", tc.name, got, tc.vendor)
		}
	}
}

func TestRecommendLLMBackend(t *testing.T) {
	if got := RecommendLLMBackend("disabled"); got != BackendCPU {
		t.Errorf("RecommendLLMBackend(disabled) = %q, want %q", got, BackendCPU)
	}
}
