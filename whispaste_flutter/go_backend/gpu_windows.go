//go:build windows

package main

import (
	"encoding/binary"
	"os/exec"
	"strconv"
	"strings"

	"golang.org/x/sys/windows/registry"
)

func detectGPU() GPUInfo {
	// NVIDIA first (most detailed info via nvidia-smi)
	if info, ok := detectNVIDIA(); ok && info.VRAM >= autoMinVRAMCUDA {
		return info
	}

	// Registry fallback for AMD/Intel
	nv, nvOK := detectNVIDIA()
	reg := detectViaRegistry()

	if reg.Detected && (!nvOK || reg.VRAM > nv.VRAM) {
		return reg
	}
	if nvOK {
		return nv
	}
	if reg.Detected {
		return reg
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
		return GPUInfo{Vendor: "nvidia", Backend: "cuda", Name: line, Detected: true}, true
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

const displayAdapterClassGUID = `SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

func detectViaRegistry() GPUInfo {
	key, err := registry.OpenKey(registry.LOCAL_MACHINE, displayAdapterClassGUID,
		registry.ENUMERATE_SUB_KEYS|registry.READ)
	if err != nil {
		return GPUInfo{}
	}
	defer key.Close()

	subkeys, err := key.ReadSubKeyNames(-1)
	if err != nil {
		return GPUInfo{}
	}

	var best GPUInfo
	for _, subkey := range subkeys {
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
		if vendor == "nvidia" || vendor == "unknown" {
			sub.Close()
			continue
		}

		vramMB := readVRAMFromRegistry(sub)
		sub.Close()

		info := GPUInfo{
			Name:     name,
			Vendor:   vendor,
			VRAM:     vramMB,
			Backend:  "vulkan",
			Detected: true,
		}

		if info.VRAM > best.VRAM {
			best = info
		}
	}

	return best
}

func readVRAMFromRegistry(key registry.Key) int {
	if val, _, err := key.GetBinaryValue("HardwareInformation.qwMemorySize"); err == nil && len(val) >= 8 {
		b := binary.LittleEndian.Uint64(val)
		return int(b / (1024 * 1024))
	}
	if val, _, err := key.GetBinaryValue("HardwareInformation.MemorySize"); err == nil && len(val) >= 4 {
		b := binary.LittleEndian.Uint32(val)
		return int(b / (1024 * 1024))
	}
	if val, _, err := key.GetIntegerValue("HardwareInformation.MemorySize"); err == nil {
		return int(val / (1024 * 1024))
	}
	return 0
}

func vendorFromName(name string) string {
	lower := strings.ToLower(name)
	switch {
	case strings.Contains(lower, "nvidia") || strings.Contains(lower, "geforce") || strings.Contains(lower, "quadro"):
		return "nvidia"
	case strings.Contains(lower, "amd") || strings.Contains(lower, "radeon") || strings.Contains(lower, "ati"):
		return "amd"
	case strings.Contains(lower, "intel") || strings.Contains(lower, "iris") || strings.Contains(lower, "uhd graphics") || strings.Contains(lower, "arc "):
		return "intel"
	default:
		return "unknown"
	}
}
