// Package gpu provides NVIDIA GPU detection for Windows.
// It checks for CUDA availability and VRAM capacity to determine
// whether GPU-accelerated inference binaries should be used.
package gpu

import (
	"os/exec"
	"strconv"
	"strings"
	"sync"
)

// Info describes the detected GPU capabilities.
type Info struct {
	Available     bool   // true if a CUDA-capable GPU was detected
	Name          string // GPU name (e.g. "NVIDIA GeForce RTX 4090")
	VRAMMBytes    int    // total VRAM in MB
	DriverVersion string // NVIDIA driver version
}

var (
	cachedInfo *Info
	detectOnce sync.Once
)

// Detect returns GPU information. Results are cached after the first call.
func Detect() Info {
	detectOnce.Do(func() {
		info := detectNVIDIA()
		cachedInfo = &info
	})
	return *cachedInfo
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
		return Info{Available: true, Name: line}
	}

	vram, _ := strconv.Atoi(strings.TrimSpace(parts[1]))

	return Info{
		Available:     true,
		Name:          strings.TrimSpace(parts[0]),
		VRAMMBytes:    vram,
		DriverVersion: strings.TrimSpace(parts[2]),
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
func RecommendSTTAssetKey(gpuMode string) string {
	if ShouldUseGPU(gpuMode, 2048) { // 2GB minimum for STT
		return "cuda"
	}
	return "bin-x64"
}

// RecommendLLMAssetKey returns the download asset key for the LLM server.
func RecommendLLMAssetKey(gpuMode string) string {
	if ShouldUseGPU(gpuMode, 2048) { // 2GB minimum for LLM
		return "win-cuda-cu12.2-x64"
	}
	return "win-cpu-x64"
}
