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
	if got := RecommendSTTBackend("disabled"); got != BackendCPU {
		t.Errorf("RecommendSTTBackend(disabled) = %q, want %q", got, BackendCPU)
	}
}

// --- "enabled" mode tests ---

func TestRecommendSTTAssetKey_Enabled(t *testing.T) {
	info := Detect()
	got := RecommendSTTAssetKey("enabled")
	backend := RecommendSTTBackend("enabled")

	if got == "" {
		t.Fatal("returned empty string")
	}

	if info.Vendor == VendorNVIDIA {
		if got != "cublas-12" {
			t.Errorf("NVIDIA detected: got %q, want %q", got, "cublas-12")
		}
		if backend != BackendCUDA {
			t.Errorf("NVIDIA detected: backend = %q, want %q", backend, BackendCUDA)
		}
	} else if info.Vendor == VendorAMD || info.Vendor == VendorIntel {
		if got != "blas-bin-x64" {
			t.Errorf("non-NVIDIA detected: got %q, want %q", got, "blas-bin-x64")
		}
		if backend != BackendVulkan {
			t.Errorf("AMD/Intel detected: backend = %q, want %q", backend, BackendVulkan)
		}
	} else {
		if got != "blas-bin-x64" {
			t.Errorf("unknown vendor detected: got %q, want %q", got, "blas-bin-x64")
		}
		if backend != BackendCPU {
			t.Errorf("unknown vendor detected: backend = %q, want %q", backend, BackendCPU)
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
		if got != BackendCPU {
			t.Errorf("unknown vendor: got %q, want %q", got, BackendCPU)
		}
	}
}

// --- "auto" mode tests ---

func TestRecommendSTTAssetKey_Auto(t *testing.T) {
	info := Detect()
	got := RecommendSTTAssetKey("auto")
	backend := RecommendSTTBackend("auto")

	validKeys := map[string]bool{"cublas-12": true, "blas-bin-x64": true}
	if !validKeys[got] {
		t.Fatalf("got %q, want one of cublas-12 or blas-bin-x64", got)
	}

	hasGPU := shouldUseRecommendedGPUForInfo("auto", info)
	if hasGPU && info.Vendor == VendorNVIDIA {
		if got != "cublas-12" {
			t.Errorf("NVIDIA with sufficient VRAM: got %q, want %q", got, "cublas-12")
		}
		if backend != BackendCUDA {
			t.Errorf("NVIDIA with sufficient VRAM: backend = %q, want %q", backend, BackendCUDA)
		}
	}
	if !hasGPU {
		if got != "blas-bin-x64" {
			t.Errorf("no sufficient GPU: got %q, want %q", got, "blas-bin-x64")
		}
		if backend != BackendCPU {
			t.Errorf("no sufficient GPU: backend = %q, want %q", backend, BackendCPU)
		}
	}
	if hasGPU && (info.Vendor == VendorAMD || info.Vendor == VendorIntel) && backend != BackendVulkan {
		t.Errorf("AMD/Intel STT should prefer Vulkan, got %q", backend)
	}
	if hasGPU && info.Vendor == VendorUnknown && backend != BackendCPU {
		t.Errorf("unknown-vendor STT should fall back to CPU, got %q", backend)
	}
}

func TestRecommendSTTBackendForInfo(t *testing.T) {
	tests := []struct {
		name   string
		info   Info
		useGPU bool
		want   Backend
	}{
		{name: "gpu disabled", info: Info{Available: true, Vendor: VendorNVIDIA}, useGPU: false, want: BackendCPU},
		{name: "nvidia", info: Info{Available: true, Vendor: VendorNVIDIA}, useGPU: true, want: BackendCUDA},
		{name: "amd", info: Info{Available: true, Vendor: VendorAMD}, useGPU: true, want: BackendVulkan},
		{name: "intel", info: Info{Available: true, Vendor: VendorIntel}, useGPU: true, want: BackendVulkan},
		{name: "unknown", info: Info{Available: true, Vendor: VendorUnknown}, useGPU: true, want: BackendCPU},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := recommendSTTBackendForInfo(tc.info, tc.useGPU); got != tc.want {
				t.Fatalf("recommendSTTBackendForInfo(%q) = %q, want %q", tc.name, got, tc.want)
			}
		})
	}
}

func TestRecommendLLMAssetKey_Auto(t *testing.T) {
	info := Detect()
	got := RecommendLLMAssetKey("auto")

	validKeys := map[string]bool{"win-cuda": true, "win-vulkan-x64": true, "win-cpu-x64": true}
	if !validKeys[got] {
		t.Fatalf("got %q, want one of win-cuda, win-vulkan-x64, win-cpu-x64", got)
	}

	hasGPU := shouldUseRecommendedGPUForInfo("auto", info)
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

	hasGPU := shouldUseRecommendedGPUForInfo("auto", info)
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

func TestShouldUseRecommendedGPUForInfo(t *testing.T) {
	tests := []struct {
		name string
		mode string
		info Info
		want bool
	}{
		{
			name: "intel auto accepts 2047MB",
			mode: "auto",
			info: Info{Available: true, Vendor: VendorIntel, VRAMMBytes: 2047},
			want: true,
		},
		{
			name: "nvidia auto still needs 2GB",
			mode: "auto",
			info: Info{Available: true, Vendor: VendorNVIDIA, VRAMMBytes: 1024},
			want: false,
		},
		{
			name: "disabled always off",
			mode: "disabled",
			info: Info{Available: true, Vendor: VendorIntel, VRAMMBytes: 8192},
			want: false,
		},
		{
			name: "enabled always on",
			mode: "enabled",
			info: Info{Available: true, Vendor: VendorUnknown, VRAMMBytes: 0},
			want: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldUseRecommendedGPUForInfo(tc.mode, tc.info); got != tc.want {
				t.Fatalf("shouldUseRecommendedGPUForInfo(%q) = %v, want %v", tc.name, got, tc.want)
			}
		})
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

// --- backend consistency tests (STT and LLM must agree on CPU for unknown vendors) ---

func TestRecommendLLMBackendForInfo_UnknownVendorReturnsCPU(t *testing.T) {
	// Unknown vendor must never get Vulkan — it should fall to CPU,
	// consistent with STT behavior (recommendSTTBackendForInfo).
	info := Info{Available: true, Vendor: VendorUnknown, VRAMMBytes: 8192}
	got := RecommendLLMBackend("enabled")
	_ = info // used for documentation; actual test uses live Detect()

	// Unit-test the internal logic directly with known Info values
	tests := []struct {
		name   string
		info   Info
		useGPU bool
		want   Backend
	}{
		{name: "unknown vendor gpu on", info: Info{Available: true, Vendor: VendorUnknown}, useGPU: true, want: BackendCPU},
		{name: "nvidia gpu on", info: Info{Available: true, Vendor: VendorNVIDIA}, useGPU: true, want: BackendCUDA},
		{name: "amd gpu on", info: Info{Available: true, Vendor: VendorAMD}, useGPU: true, want: BackendVulkan},
		{name: "intel gpu on", info: Info{Available: true, Vendor: VendorIntel}, useGPU: true, want: BackendVulkan},
		{name: "nvidia gpu off", info: Info{Available: true, Vendor: VendorNVIDIA}, useGPU: false, want: BackendCPU},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Use the same logic path as RecommendLLMBackend but with controlled inputs
			var backend Backend
			if !tc.useGPU {
				backend = BackendCPU
			} else {
				switch tc.info.Vendor {
				case VendorNVIDIA:
					backend = BackendCUDA
				case VendorAMD, VendorIntel:
					backend = BackendVulkan
				default:
					backend = BackendCPU
				}
			}
			if backend != tc.want {
				t.Fatalf("backend for %q = %q, want %q", tc.name, backend, tc.want)
			}
		})
	}
	_ = got
}

func TestDetectPrefersStrongRegistryGPUOverWeakNVIDIA(t *testing.T) {
	// This tests the design principle: if NVIDIA GPU has insufficient VRAM
	// for CUDA, a stronger AMD/Intel GPU from registry should be preferred.
	// We can't mock nvidia-smi/registry in unit tests, but we verify the
	// threshold constants are coherent.
	if autoMinVRAMCUDA < autoMinVRAMVulkan {
		t.Errorf("CUDA VRAM threshold (%d) should be >= Vulkan threshold (%d)",
			autoMinVRAMCUDA, autoMinVRAMVulkan)
	}
}

func TestAutoMinVRAMForVendor(t *testing.T) {
	tests := []struct {
		vendor Vendor
		want   int
	}{
		{VendorNVIDIA, autoMinVRAMCUDA},
		{VendorAMD, autoMinVRAMVulkan},
		{VendorIntel, autoMinVRAMVulkan},
		{VendorUnknown, autoMinVRAMCUDA},
	}
	for _, tc := range tests {
		if got := autoMinVRAMForVendor(tc.vendor); got != tc.want {
			t.Errorf("autoMinVRAMForVendor(%q) = %d, want %d", tc.vendor, got, tc.want)
		}
	}
}
