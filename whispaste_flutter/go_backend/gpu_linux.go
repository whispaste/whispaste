//go:build linux

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

func detectGPU() GPUInfo {
	// NVIDIA via nvidia-smi (works on Linux too)
	if info, ok := detectNVIDIA(); ok {
		return info
	}

	// Linux sysfs fallback for AMD/Intel
	if info, ok := detectViaSysfs(); ok {
		return info
	}

	return GPUInfo{
		Name:     "No GPU detected",
		Vendor:   "unknown",
		Backend:  "cpu",
		Detected: false,
	}
}

func detectNVIDIA() (GPUInfo, bool) {
	out, err := exec.Command("nvidia-smi",
		"--query-gpu=name,memory.total,driver_version",
		"--format=csv,noheader,nounits").Output()
	if err != nil {
		return GPUInfo{}, false
	}

	line := strings.TrimSpace(string(out))
	if line == "" {
		return GPUInfo{}, false
	}

	lines := strings.Split(line, "\n")
	parts := strings.SplitN(strings.TrimSpace(lines[0]), ", ", 3)
	if len(parts) < 3 {
		return GPUInfo{Name: line, Vendor: "nvidia", Backend: "cuda", Detected: true}, true
	}

	vram, _ := strconv.Atoi(strings.TrimSpace(parts[1]))
	return GPUInfo{
		Name:     strings.TrimSpace(parts[0]),
		Vendor:   "nvidia",
		VRAM:     vram,
		Backend:  "cuda",
		Driver:   strings.TrimSpace(parts[2]),
		Detected: true,
	}, true
}

func detectViaSysfs() (GPUInfo, bool) {
	// Read /sys/class/drm/card*/device/vendor
	cards, _ := filepath.Glob("/sys/class/drm/card[0-9]*/device/vendor")
	for _, vendorPath := range cards {
		data, err := os.ReadFile(vendorPath)
		if err != nil {
			continue
		}

		vendorID := strings.TrimSpace(string(data))
		deviceDir := filepath.Dir(vendorPath)

		var vendor, backend string
		switch vendorID {
		case "0x1002": // AMD
			vendor = "amd"
			backend = "vulkan"
		case "0x8086": // Intel
			vendor = "intel"
			backend = "vulkan"
		default:
			continue
		}

		// Try to get device name
		name := vendor + " GPU"
		if productData, err := os.ReadFile(filepath.Join(deviceDir, "label")); err == nil {
			name = strings.TrimSpace(string(productData))
		}

		// Try to read VRAM from /sys/class/drm/card*/device/mem_info_vram_total
		cardDir := filepath.Dir(deviceDir)
		var vramMB int
		if vramData, err := os.ReadFile(filepath.Join(cardDir, "device", "mem_info_vram_total")); err == nil {
			if vramBytes, err := strconv.ParseInt(strings.TrimSpace(string(vramData)), 10, 64); err == nil {
				vramMB = int(vramBytes / (1024 * 1024))
			}
		}

		return GPUInfo{
			Name:     name,
			Vendor:   vendor,
			VRAM:     vramMB,
			Backend:  backend,
			Detected: true,
		}, true
	}

	return GPUInfo{}, false
}
