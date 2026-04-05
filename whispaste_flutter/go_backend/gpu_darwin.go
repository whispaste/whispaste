//go:build darwin

package main

import (
	"os/exec"
	"strings"
)

func detectGPU() GPUInfo {
	// macOS: use system_profiler for GPU info
	// Apple Silicon has unified memory, no traditional discrete GPU
	out, err := exec.Command("system_profiler", "SPDisplaysDataType", "-detailLevel", "mini").Output()
	if err != nil {
		return GPUInfo{
			Name:     "Unknown GPU",
			Vendor:   "unknown",
			Backend:  "cpu",
			Detected: false,
		}
	}

	output := string(out)

	// Parse chipset/GPU name
	name := "Apple GPU"
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Chipset Model:") {
			name = strings.TrimSpace(strings.TrimPrefix(trimmed, "Chipset Model:"))
			break
		}
	}

	vendor := "apple"
	backend := "cpu" // Metal is macOS-native but whisper.cpp/llama.cpp use CPU on macOS

	lower := strings.ToLower(name)
	if strings.Contains(lower, "nvidia") || strings.Contains(lower, "geforce") {
		vendor = "nvidia"
		backend = "cpu" // NVIDIA on macOS is legacy, no CUDA support
	} else if strings.Contains(lower, "amd") || strings.Contains(lower, "radeon") {
		vendor = "amd"
		backend = "cpu" // No Vulkan on macOS
	} else if strings.Contains(lower, "intel") {
		vendor = "intel"
		backend = "cpu"
	} else if strings.Contains(lower, "apple") {
		vendor = "apple"
		backend = "metal" // Apple Silicon uses Metal
	}

	// Parse VRAM (macOS reports it for discrete GPUs)
	var vramMB int
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "VRAM") || strings.Contains(trimmed, "Memory:") {
			// Extract number — "VRAM (Total): 8 GB" or similar
			for _, word := range strings.Fields(trimmed) {
				if v := parseInt(word); v > 0 {
					if strings.Contains(trimmed, "GB") {
						vramMB = v * 1024
					} else {
						vramMB = v
					}
					break
				}
			}
			break
		}
	}

	return GPUInfo{
		Name:     name,
		Vendor:   vendor,
		VRAM:     vramMB,
		Backend:  backend,
		Detected: true,
	}
}

func parseInt(s string) int {
	var n int
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}
