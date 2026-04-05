package main

// #include <stdlib.h>
import "C"
import (
	"encoding/json"
	"unsafe"
)

// --------------------------------------------------------------------
// FFI Bridge — Exports C-compatible functions for Flutter dart:ffi
// --------------------------------------------------------------------

// GPUInfo holds detected GPU information returned to Flutter.
type GPUInfo struct {
	Name     string `json:"name"`
	Vendor   string `json:"vendor"`   // "nvidia", "amd", "intel", "unknown"
	VRAM     int    `json:"vram_mb"`  // In megabytes, 0 if unknown
	Backend  string `json:"backend"`  // "cuda", "vulkan", "cpu"
	Driver   string `json:"driver"`   // Driver version string
	Detected bool   `json:"detected"`
}

// DetectGPU returns JSON-encoded GPU info. Caller must free with FreeString.
//
//export DetectGPU
func DetectGPU() *C.char {
	info := detectGPU()
	data, _ := json.Marshal(info)
	return C.CString(string(data))
}

// RecommendBackend returns the recommended inference backend ("cuda", "vulkan", "cpu").
// Caller must free with FreeString.
//
//export RecommendBackend
func RecommendBackend() *C.char {
	info := detectGPU()
	return C.CString(info.Backend)
}

// RecommendSTTAsset returns the download asset key for the STT server binary.
// gpuMode: "auto", "enabled", "disabled". Caller must free with FreeString.
//
//export RecommendSTTAsset
func RecommendSTTAsset(gpuMode *C.char) *C.char {
	mode := C.GoString(gpuMode)
	info := detectGPU()
	asset := recommendSTTAsset(mode, info)
	return C.CString(asset)
}

// RecommendLLMAsset returns the download asset key for the LLM server binary.
// gpuMode: "auto", "enabled", "disabled". Caller must free with FreeString.
//
//export RecommendLLMAsset
func RecommendLLMAsset(gpuMode *C.char) *C.char {
	mode := C.GoString(gpuMode)
	info := detectGPU()
	asset := recommendLLMAsset(mode, info)
	return C.CString(asset)
}

// GetVersion returns the bridge version. Caller must free with FreeString.
//
//export GetVersion
func GetVersion() *C.char {
	return C.CString("1.2.0")
}

// FreeString frees a C string allocated by this library.
//
//export FreeString
func FreeString(s *C.char) {
	C.free(unsafe.Pointer(s))
}

// --- Backend recommendation logic (mirrors internal/gpu/detect.go) ---

const (
	autoMinVRAMCUDA   = 2048
	autoMinVRAMVulkan = 0
)

func shouldUseGPU(mode string, info GPUInfo) bool {
	switch mode {
	case "disabled":
		return false
	case "enabled":
		return true
	default: // "auto"
		minVRAM := autoMinVRAMCUDA
		if info.Vendor == "amd" || info.Vendor == "intel" {
			minVRAM = autoMinVRAMVulkan
		}
		return info.Detected && info.VRAM >= minVRAM
	}
}

func recommendSTTAsset(gpuMode string, info GPUInfo) string {
	if !shouldUseGPU(gpuMode, info) {
		return "blas-bin-x64"
	}
	if info.Vendor == "nvidia" {
		return "cublas-12"
	}
	return "blas-bin-x64"
}

func recommendLLMAsset(gpuMode string, info GPUInfo) string {
	if !shouldUseGPU(gpuMode, info) {
		return "cpu-x64"
	}
	switch info.Vendor {
	case "nvidia":
		return "cuda"
	default:
		return "vulkan-x64"
	}
}

func main() {}
