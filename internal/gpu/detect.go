// Package gpu provides multi-vendor GPU detection for Windows.
// It detects NVIDIA (via nvidia-smi), AMD, and Intel GPUs (via Windows
// registry) and recommends the best inference backend for each vendor.
package gpu

import (
	"encoding/binary"
	"os/exec"
	"strconv"
	"strings"
	"sync"

	"golang.org/x/sys/windows/registry"
)

// Vendor identifies the GPU manufacturer.
type Vendor string

const (
	VendorNVIDIA  Vendor = "nvidia"
	VendorAMD     Vendor = "amd"
	VendorIntel   Vendor = "intel"
	VendorUnknown Vendor = "unknown"
)

// Backend identifies the GPU compute backend.
type Backend string

const (
	BackendCUDA   Backend = "cuda"
	BackendVulkan Backend = "vulkan"
	BackendCPU    Backend = "cpu"
)

// Info describes the detected GPU capabilities.
type Info struct {
	Available     bool    // true if a usable GPU was detected
	Vendor        Vendor  // GPU vendor (nvidia, amd, intel, unknown)
	Backend       Backend // recommended compute backend
	Name          string  // GPU name (e.g. "NVIDIA GeForce RTX 4090")
	VRAMMBytes    int     // total VRAM in MB
	DriverVersion string  // driver version (NVIDIA only)
}

var (
	cachedInfo *Info
	detectOnce sync.Once
)

// Detect returns GPU information. Results are cached after the first call.
func Detect() Info {
	detectOnce.Do(func() {
		info := detect()
		cachedInfo = &info
	})
	return *cachedInfo
}

// detect probes for GPUs: NVIDIA first (via nvidia-smi for detailed info),
// then falls back to Windows registry for AMD/Intel detection.
func detect() Info {
	if info := detectNVIDIA(); info.Available {
		return info
	}
	return detectViaRegistry()
}

// detectNVIDIA probes for NVIDIA GPU via nvidia-smi.
func detectNVIDIA() Info {
	out, err := exec.Command("nvidia-smi",
		"--query-gpu=name,memory.total,driver_version",
		"--format=csv,noheader,nounits").Output()
	if err != nil {
		return Info{}
	}

	line := strings.TrimSpace(string(out))
	if line == "" {
		return Info{}
	}

	// Handle multi-GPU: use first GPU
	lines := strings.Split(line, "\n")
	parts := strings.SplitN(strings.TrimSpace(lines[0]), ", ", 3)
	if len(parts) < 3 {
		return Info{Available: true, Vendor: VendorNVIDIA, Backend: BackendCUDA, Name: line}
	}

	vram, _ := strconv.Atoi(strings.TrimSpace(parts[1]))

	return Info{
		Available:     true,
		Vendor:        VendorNVIDIA,
		Backend:       BackendCUDA,
		Name:          strings.TrimSpace(parts[0]),
		VRAMMBytes:    vram,
		DriverVersion: strings.TrimSpace(parts[2]),
	}
}

// displayAdapterClassGUID is the Windows device class GUID for display adapters.
const displayAdapterClassGUID = `SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

// detectViaRegistry enumerates display adapters from the Windows registry
// to find AMD or Intel GPUs. This catches discrete GPUs and iGPUs alike.
func detectViaRegistry() Info {
	key, err := registry.OpenKey(registry.LOCAL_MACHINE, displayAdapterClassGUID,
		registry.ENUMERATE_SUB_KEYS|registry.READ)
	if err != nil {
		return Info{}
	}
	defer key.Close()

	subkeys, err := key.ReadSubKeyNames(-1)
	if err != nil {
		return Info{}
	}

	// Prefer discrete GPUs (AMD/Intel dGPU) over iGPUs.
	// Return the first non-NVIDIA GPU found — NVIDIA is already handled above.
	var bestInfo Info
	for _, subkey := range subkeys {
		// Subkeys are "0000", "0001", etc. Skip non-numeric subkeys like "Properties"
		if len(subkey) != 4 {
			continue
		}

		sub, err := registry.OpenKey(key, subkey, registry.READ)
		if err != nil {
			continue
		}

		name, _, _ := sub.GetStringValue("DriverDesc")
		if name == "" {
			sub.Close()
			continue
		}

		vendor := vendorFromName(name)
		if vendor == VendorNVIDIA || vendor == VendorUnknown {
			sub.Close()
			continue // NVIDIA handled by nvidia-smi; skip unknown
		}

		vramMB := readVRAMFromRegistry(sub)
		sub.Close()

		info := Info{
			Available:  true,
			Vendor:     vendor,
			Backend:    BackendVulkan, // Vulkan: universal GPU backend for AMD + Intel
			Name:       name,
			VRAMMBytes: vramMB,
		}

		// Prefer GPUs with more VRAM (typically discrete > integrated)
		if info.VRAMMBytes > bestInfo.VRAMMBytes {
			bestInfo = info
		}
	}

	return bestInfo
}

// readVRAMFromRegistry reads VRAM size from the registry subkey.
// Tries HardwareInformation.qwMemorySize (8-byte QWORD) first,
// then falls back to HardwareInformation.MemorySize (4-byte DWORD).
func readVRAMFromRegistry(key registry.Key) int {
	// Try 8-byte QWORD value first (modern drivers)
	if val, _, err := key.GetBinaryValue("HardwareInformation.qwMemorySize"); err == nil && len(val) >= 8 {
		bytes := binary.LittleEndian.Uint64(val)
		return int(bytes / (1024 * 1024))
	}

	// Try 4-byte DWORD value (older drivers)
	if val, _, err := key.GetBinaryValue("HardwareInformation.MemorySize"); err == nil && len(val) >= 4 {
		bytes := binary.LittleEndian.Uint32(val)
		return int(bytes / (1024 * 1024))
	}

	// Try integer value
	if val, _, err := key.GetIntegerValue("HardwareInformation.MemorySize"); err == nil {
		return int(val / (1024 * 1024))
	}

	return 0
}

// vendorFromName identifies the GPU vendor from the device description.
func vendorFromName(name string) Vendor {
	lower := strings.ToLower(name)
	switch {
	case strings.Contains(lower, "nvidia") || strings.Contains(lower, "geforce") || strings.Contains(lower, "quadro"):
		return VendorNVIDIA
	case strings.Contains(lower, "amd") || strings.Contains(lower, "radeon") || strings.Contains(lower, "ati"):
		return VendorAMD
	case strings.Contains(lower, "intel") || strings.Contains(lower, "iris") || strings.Contains(lower, "uhd graphics") || strings.Contains(lower, "arc "):
		return VendorIntel
	default:
		return VendorUnknown
	}
}

// HasSufficientVRAM returns true if the GPU has at least minMB of VRAM.
func (g Info) HasSufficientVRAM(minMB int) bool {
	return g.Available && g.VRAMMBytes >= minMB
}

// ShouldUseGPU returns true if GPU acceleration should be used,
// based on the user's preference and detected hardware.
// mode: "auto" (detect), "enabled" (force), "disabled" (never)
func ShouldUseGPU(mode string, minVRAMMB int) bool {
	switch mode {
	case "disabled":
		return false
	case "enabled":
		return true
	default: // "auto" or ""
		info := Detect()
		return info.HasSufficientVRAM(minVRAMMB)
	}
}

// RecommendSTTAssetKey returns the download asset key for the STT server.
// whisper.cpp releases: "cublas-12" (NVIDIA CUDA) or "blas-bin-x64" (CPU+OpenBLAS).
// No Vulkan/HIP/SYCL builds exist for whisper.cpp, so non-NVIDIA GPUs get OpenBLAS.
func RecommendSTTAssetKey(gpuMode string) string {
	info := Detect()
	useGPU := ShouldUseGPU(gpuMode, 2048)

	if useGPU && info.Vendor == VendorNVIDIA {
		return "cublas-12" // matches whisper-cublas-12.*.0-bin-x64.zip
	}
	return "blas-bin-x64" // OpenBLAS CPU build: faster than plain bin-x64
}

// RecommendLLMAssetKey returns the download asset key for the LLM server.
// llama.cpp releases: CUDA (NVIDIA), Vulkan (AMD/Intel/universal), or CPU.
func RecommendLLMAssetKey(gpuMode string) string {
	info := Detect()
	useGPU := ShouldUseGPU(gpuMode, 2048)

	if !useGPU {
		return "win-cpu-x64"
	}

	switch info.Vendor {
	case VendorNVIDIA:
		return "win-cuda" // matches win-cuda-12.4-x64, win-cuda-13.1-x64, etc.
	default:
		// Vulkan: universal GPU backend — works on AMD, Intel, and NVIDIA
		return "win-vulkan-x64"
	}
}

// RecommendLLMBackend returns the compute backend to use for the LLM server.
func RecommendLLMBackend(gpuMode string) Backend {
	if !ShouldUseGPU(gpuMode, 2048) {
		return BackendCPU
	}
	info := Detect()
	switch info.Vendor {
	case VendorNVIDIA:
		return BackendCUDA
	case VendorAMD, VendorIntel:
		return BackendVulkan
	default:
		return BackendVulkan
	}
}
