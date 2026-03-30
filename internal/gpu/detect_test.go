package gpu

import (
	"strings"
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

// --- "enabled" mode tests ---

func TestRecommendSTTAssetKey_Enabled(t *testing.T) {
	info := Detect()
	got := RecommendSTTAssetKey("enabled")

	if got == "" {
		t.Fatal("returned empty string")
	}

	// "enabled" forces GPU on; only NVIDIA gets CUDA (whisper.cpp has no Vulkan builds)
	if info.Vendor == VendorNVIDIA {
		if got != "cublas-12" {
			t.Errorf("NVIDIA detected: got %q, want %q", got, "cublas-12")
		}
	} else {
		if got != "blas-bin-x64" {
			t.Errorf("non-NVIDIA detected: got %q, want %q", got, "blas-bin-x64")
		}
	}
}

func TestRecommendLLMAssetKey_Enabled(t *testing.T) {
	info := Detect()
	got := RecommendLLMAssetKey("enabled")

	if got == "" {
		t.Fatal("returned empty string")
	}

	switch info.Vendor {
	case VendorNVIDIA:
		if got != "win-cuda" {
			t.Errorf("NVIDIA detected: got %q, want %q", got, "win-cuda")
		}
	default:
		// AMD, Intel, or no GPU all get Vulkan when forced enabled
		if got != "win-vulkan-x64" {
			t.Errorf("vendor %q: got %q, want %q", info.Vendor, got, "win-vulkan-x64")
		}
	}
}

func TestRecommendLLMBackend_Enabled(t *testing.T) {
	info := Detect()
	got := RecommendLLMBackend("enabled")

	switch info.Vendor {
	case VendorNVIDIA:
		if got != BackendCUDA {
			t.Errorf("NVIDIA detected: got %q, want %q", got, BackendCUDA)
		}
	case VendorAMD, VendorIntel:
		if got != BackendVulkan {
			t.Errorf("vendor %q: got %q, want %q", info.Vendor, got, BackendVulkan)
		}
	default:
		if got != BackendVulkan {
			t.Errorf("unknown vendor: got %q, want %q", got, BackendVulkan)
		}
	}
}

// --- "auto" mode tests ---

func TestRecommendSTTAssetKey_Auto(t *testing.T) {
	info := Detect()
	got := RecommendSTTAssetKey("auto")

	validKeys := map[string]bool{"cublas-12": true, "blas-bin-x64": true}
	if !validKeys[got] {
		t.Fatalf("got %q, want one of cublas-12 or blas-bin-x64", got)
	}

	hasGPU := info.Available && info.HasSufficientVRAM(2048)
	if hasGPU && info.Vendor == VendorNVIDIA {
		if got != "cublas-12" {
			t.Errorf("NVIDIA with sufficient VRAM: got %q, want %q", got, "cublas-12")
		}
	}
	if !hasGPU {
		if got != "blas-bin-x64" {
			t.Errorf("no sufficient GPU: got %q, want %q", got, "blas-bin-x64")
		}
	}
}

func TestRecommendLLMAssetKey_Auto(t *testing.T) {
	info := Detect()
	got := RecommendLLMAssetKey("auto")

	validKeys := map[string]bool{"win-cuda": true, "win-vulkan-x64": true, "win-cpu-x64": true}
	if !validKeys[got] {
		t.Fatalf("got %q, want one of win-cuda, win-vulkan-x64, win-cpu-x64", got)
	}

	hasGPU := info.Available && info.HasSufficientVRAM(2048)
	if !hasGPU {
		if got != "win-cpu-x64" {
			t.Errorf("no sufficient GPU: got %q, want %q", got, "win-cpu-x64")
		}
	}
	if hasGPU && info.Vendor == VendorNVIDIA {
		if got != "win-cuda" {
			t.Errorf("NVIDIA with sufficient VRAM: got %q, want %q", got, "win-cuda")
		}
	}
}

func TestRecommendLLMBackend_Auto(t *testing.T) {
	info := Detect()
	got := RecommendLLMBackend("auto")

	validBackends := map[Backend]bool{BackendCUDA: true, BackendVulkan: true, BackendCPU: true}
	if !validBackends[got] {
		t.Fatalf("got %q, want one of cuda, vulkan, cpu", got)
	}

	hasGPU := info.Available && info.HasSufficientVRAM(2048)
	if !hasGPU {
		if got != BackendCPU {
			t.Errorf("no sufficient GPU: got %q, want %q", got, BackendCPU)
		}
	}
	if hasGPU && info.Vendor == VendorNVIDIA {
		if got != BackendCUDA {
			t.Errorf("NVIDIA with sufficient VRAM: got %q, want %q", got, BackendCUDA)
		}
	}
}

// --- "disabled" mode: explicit per-function tests ---

func TestRecommendSTTAssetKey_DisabledReturnsNoGPU(t *testing.T) {
	got := RecommendSTTAssetKey("disabled")
	if got != "blas-bin-x64" {
		t.Errorf("got %q, want %q", got, "blas-bin-x64")
	}
	for _, substr := range []string{"cuda", "cublas", "vulkan"} {
		if strings.Contains(strings.ToLower(got), substr) {
			t.Errorf("disabled key %q must not contain %q", got, substr)
		}
	}
}

func TestRecommendLLMAssetKey_DisabledReturnsNoGPU(t *testing.T) {
	got := RecommendLLMAssetKey("disabled")
	if got != "win-cpu-x64" {
		t.Errorf("got %q, want %q", got, "win-cpu-x64")
	}
	for _, substr := range []string{"cuda", "vulkan"} {
		if strings.Contains(strings.ToLower(got), substr) {
			t.Errorf("disabled key %q must not contain %q", got, substr)
		}
	}
}
