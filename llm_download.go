package main

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/gpu"
	"github.com/whispaste/whispaste/internal/models"
)

// LLMModelDef describes a downloadable local LLM model.
type LLMModelDef struct {
	ID          string // unique identifier (e.g. "smollm2")
	Name        string // display name
	URL         string // GGUF download URL
	Size        int64  // approximate download size in bytes
	Filename    string // local filename for the GGUF
	Langs       int    // number of supported languages
	MinRAMBytes uint64 // minimum RAM for usable performance
	RecRAMBytes uint64 // recommended RAM for good performance
}

const _llmGB = 1024 * 1024 * 1024

// LLMModels is the registry of available local LLM models.
var LLMModels = map[string]LLMModelDef{
	"smollm2": {
		ID:          "smollm2",
		Name:        "SmolLM2",
		URL:         "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf",
		Size:        283_000_000,
		Filename:    "smollm2.gguf",
		Langs:       6,
		MinRAMBytes: 4 * _llmGB,
		RecRAMBytes: 4 * _llmGB,
	},
	"qwen2.5-0.5b": {
		ID:          "qwen2.5-0.5b",
		Name:        "Qwen2.5-0.5B",
		URL:         "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
		Size:        491_000_000,
		Filename:    "qwen2.5-0.5b.gguf",
		Langs:       29,
		MinRAMBytes: 2 * _llmGB,
		RecRAMBytes: 4 * _llmGB,
	},
	"qwen3.5-0.8b": {
		ID:          "qwen3.5-0.8b",
		Name:        "Qwen3.5-0.8B",
		URL:         "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf",
		Size:        532_517_120,
		Filename:    "qwen3.5-0.8b.gguf",
		Langs:       29,
		MinRAMBytes: 4 * _llmGB,
		RecRAMBytes: 8 * _llmGB,
	},
}

const (
	llmServerRepo = "ggml-org/llama.cpp"
)

// llmAssetKey returns the appropriate asset key based on GPU availability.
func llmAssetKey(gpuMode string) string {
	return gpu.RecommendLLMAssetKey(gpuMode)
}

// DownloadLLM downloads the llama-server binary (if needed) and a GGUF model.
// gpuMode controls asset selection: "auto" (detect), "enabled" (force CUDA), "disabled" (CPU only).
// progressFn is called with phase ("server" or "model") and percentage (0–100).
func DownloadLLM(modelID string, gpuMode string, progressFn func(phase string, pct int)) error {
	model, ok := LLMModels[modelID]
	if !ok {
		return fmt.Errorf("unknown LLM model: %s", modelID)
	}

	dir, err := LLMDir()
	if err != nil {
		return fmt.Errorf("llm dir: %w", err)
	}

	// Phase 1: Download and extract llama-server ZIP (skip if already installed)
	if !IsLLMServerInstalled() {
		if progressFn != nil {
			progressFn("server", 0)
		}
		if err := downloadAndExtractLLMServer(dir, gpuMode, func(pct int) {
			if progressFn != nil {
				progressFn("server", pct)
			}
		}); err != nil {
			return fmt.Errorf("download llama-server: %w", err)
		}
	} else {
		if progressFn != nil {
			progressFn("server", 100)
		}
	}

	// Phase 2: Download model GGUF
	if progressFn != nil {
		progressFn("model", 0)
	}
	modelDest := filepath.Join(dir, model.Filename)
	var lastPct int = -1
	if err := models.DownloadFile(model.URL, modelDest, func(downloaded, total int64) {
		if progressFn != nil {
			if total <= 0 {
				total = model.Size
			}
			pct := int(float64(downloaded) / float64(total) * 100)
			if pct > 100 {
				pct = 100
			}
			if pct != lastPct {
				lastPct = pct
				progressFn("model", pct)
			}
		}
	}); err != nil {
		return fmt.Errorf("download llm model: %w", err)
	}

	logInfo("LLM download complete: %s", modelID)
	return nil
}

// LLMReleaseAsset represents a single asset from a GitHub release.
type LLMReleaseAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

// matchLLMAsset selects the best matching LLM server asset from a list of GitHub release assets.
// Priority order:
//  1. CUDA 12 (preferred over CUDA 13 for broader compatibility)
//  2. Vulkan (fallback for AMD/Intel GPUs)
//  3. CPU (universal fallback)
func matchLLMAsset(assets []LLMReleaseAsset, assetKey string) (string, error) {
	// For CUDA, find the best available CUDA version (prefer 12.x over 13.x for driver compat)
	if assetKey == "win-cuda" {
		var bestURL string
		for _, a := range assets {
			name := strings.ToLower(a.Name)
			if strings.Contains(name, "win-cuda") &&
				strings.Contains(name, "x64") &&
				strings.HasSuffix(name, ".zip") &&
				!strings.HasPrefix(name, "cudart-") {
				// Prefer CUDA 12.x (broadest driver compatibility)
				if strings.Contains(name, "cuda-12") {
					return a.BrowserDownloadURL, nil
				}
				bestURL = a.BrowserDownloadURL
			}
		}
		if bestURL != "" {
			return bestURL, nil
		}
		// CUDA not available — try Vulkan as GPU fallback
		assetKey = "win-vulkan-x64"
	}

	// Match exact asset key (Vulkan or CPU)
	for _, a := range assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, assetKey) &&
			strings.HasSuffix(name, ".zip") &&
			!strings.HasPrefix(name, "cudart-") {
			return a.BrowserDownloadURL, nil
		}
	}

	// Fallback to CPU if requested GPU asset not found
	if assetKey != "win-cpu-x64" {
		for _, a := range assets {
			name := strings.ToLower(a.Name)
			if strings.Contains(name, "win-cpu-x64") &&
				strings.HasSuffix(name, ".zip") {
				return a.BrowserDownloadURL, nil
			}
		}
	}

	return "", fmt.Errorf("no matching asset (%s) found in latest release", assetKey)
}

// resolveLLMServerURL queries the GitHub API for the latest llama.cpp release
// and returns the download URL for the appropriate asset.
// Asset keys from gpu.RecommendLLMAssetKey:
//   - "win-cuda" → NVIDIA CUDA build (prefers latest CUDA version)
//   - "win-vulkan-x64" → Vulkan build (universal GPU: AMD, Intel, NVIDIA)
//   - "win-cpu-x64" → CPU-only build
func resolveLLMServerURL(gpuMode string) (string, error) {
	assetKey := llmAssetKey(gpuMode)
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", llmServerRepo)
	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("GitHub API request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}

	var release struct {
		Assets []LLMReleaseAsset `json:"assets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}

	return matchLLMAsset(release.Assets, assetKey)
}

// downloadAndExtractLLMServer downloads the ZIP and extracts llama-server.exe and ggml DLLs.
func downloadAndExtractLLMServer(destDir string, gpuMode string, progressFn func(pct int)) error {
	serverURL, err := resolveLLMServerURL(gpuMode)
	if err != nil {
		return fmt.Errorf("resolve server URL: %w", err)
	}
	logInfo("LLM server download URL: %s", serverURL)

	zipPath := filepath.Join(destDir, "llama-server.zip")

	var lastPct int = -1
	if err := models.DownloadFile(serverURL, zipPath, func(downloaded, total int64) {
		if progressFn != nil {
			if total <= 0 {
				total = 30 * 1024 * 1024 // ~30 MB estimated server ZIP size
			}
			pct := int(float64(downloaded) / float64(total) * 100)
			if pct > 100 {
				pct = 100
			}
			if pct != lastPct {
				lastPct = pct
				progressFn(pct)
			}
		}
	}); err != nil {
		return fmt.Errorf("downloadAndExtractLLMServer: download: %w", err)
	}
	defer os.Remove(zipPath) // clean up ZIP after extraction

	// Extract relevant files
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("open zip: %w", err)
	}
	defer r.Close()

	for _, f := range r.File {
		baseName := filepath.Base(f.Name)
		// Extract llama-server.exe and any DLLs (ggml*.dll, llama.dll, etc.)
		isRelevant := strings.EqualFold(baseName, "llama-server.exe") ||
			strings.HasSuffix(strings.ToLower(baseName), ".dll")
		if !isRelevant || f.FileInfo().IsDir() {
			continue
		}

		destPath := filepath.Join(destDir, baseName)
		// Zip Slip protection: verify extracted path stays within destDir
		if !strings.HasPrefix(filepath.Clean(destPath), filepath.Clean(destDir)+string(os.PathSeparator)) {
			logWarn("Skipping potentially unsafe zip entry: %s", f.Name)
			continue
		}
		if err := extractZipFile(f, destPath); err != nil {
			return fmt.Errorf("extract %s: %w", baseName, err)
		}
	}

	return nil
}

// extractZipFile extracts a single file from a ZIP archive to dest using atomic write.
func extractZipFile(f *zip.File, dest string) error {
	rc, err := f.Open()
	if err != nil {
		return fmt.Errorf("extractZipFile: open: %w", err)
	}
	defer rc.Close()

	tmp := dest + ".tmp"
	out, err := os.Create(tmp)
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}

	if _, err := io.Copy(out, rc); err != nil {
		out.Close()
		os.Remove(tmp)
		return fmt.Errorf("write file: %w", err)
	}

	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("close temp file: %w", err)
	}

	if err := os.Rename(tmp, dest); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("rename temp file: %w", err)
	}

	return nil
}

// DeleteLLMModel removes the GGUF file for a specific model.
func DeleteLLMModel(modelID string) error {
	model, ok := LLMModels[modelID]
	if !ok {
		return fmt.Errorf("unknown LLM model: %s", modelID)
	}
	dir, err := LLMDir()
	if err != nil {
		return fmt.Errorf("llm dir: %w", err)
	}
	modelPath := filepath.Join(dir, model.Filename)
	if err := os.Remove(modelPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove model: %w", err)
	}
	logInfo("LLM model %s deleted", modelID)
	return nil
}

// DeleteLLM removes all LLM files (server binary, model, DLLs).
func DeleteLLM() error {
	dir, err := LLMDir()
	if err != nil {
		return fmt.Errorf("llm dir: %w", err)
	}
	if err := os.RemoveAll(dir); err != nil {
		return fmt.Errorf("remove llm dir: %w", err)
	}
	logInfo("LLM files deleted")
	return nil
}

// IsLLMModelInstalled checks if the GGUF file for a specific model exists.
func IsLLMModelInstalled(modelID string) bool {
	model, ok := LLMModels[modelID]
	if !ok {
		return false
	}
	dir, err := LLMDir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, model.Filename))
	return err == nil
}

// IsLLMServerInstalled checks if llama-server.exe exists.
func IsLLMServerInstalled() bool {
	p, err := LLMServerPath()
	if err != nil {
		return false
	}
	_, err = os.Stat(p)
	return err == nil
}
