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

	"github.com/whispaste/whispaste/internal/models"
)

const (
	llmServerRepo     = "ggml-org/llama.cpp"
	llmServerAssetKey = "win-cpu-x64" // substring to match in release asset name
	llmModelURL       = "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf"
	llmModelSize      = int64(283_000_000) // approximate size for progress
)

// DownloadLLM downloads the llama-server binary and GGUF model.
// progressFn is called with phase ("server" or "model") and percentage (0–100).
func DownloadLLM(progressFn func(phase string, pct int)) error {
	dir, err := LLMDir()
	if err != nil {
		return fmt.Errorf("llm dir: %w", err)
	}

	// Phase 1: Download and extract llama-server ZIP
	if progressFn != nil {
		progressFn("server", 0)
	}
	if err := downloadAndExtractLLMServer(dir, func(pct int) {
		if progressFn != nil {
			progressFn("server", pct)
		}
	}); err != nil {
		return fmt.Errorf("download llama-server: %w", err)
	}

	// Phase 2: Download model GGUF
	if progressFn != nil {
		progressFn("model", 0)
	}
	modelDest := filepath.Join(dir, "model.gguf")
	var lastPct int = -1
	if err := models.DownloadFile(llmModelURL, modelDest, func(downloaded, total int64) {
		if progressFn != nil {
			if total <= 0 {
				total = llmModelSize
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

	logInfo("LLM download complete")
	return nil
}

// resolveLLMServerURL queries the GitHub API for the latest llama.cpp release
// and returns the download URL for the Windows CPU x64 asset.
func resolveLLMServerURL() (string, error) {
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
		Assets []struct {
			Name               string `json:"name"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}

	for _, a := range release.Assets {
		if strings.Contains(strings.ToLower(a.Name), llmServerAssetKey) &&
			strings.HasSuffix(strings.ToLower(a.Name), ".zip") {
			return a.BrowserDownloadURL, nil
		}
	}
	return "", fmt.Errorf("no matching asset (%s) found in latest release", llmServerAssetKey)
}

// downloadAndExtractLLMServer downloads the ZIP and extracts llama-server.exe and ggml DLLs.
func downloadAndExtractLLMServer(destDir string, progressFn func(pct int)) error {
	serverURL, err := resolveLLMServerURL()
	if err != nil {
		return fmt.Errorf("resolve server URL: %w", err)
	}
	logInfo("LLM server download URL: %s", serverURL)

	zipPath := filepath.Join(destDir, "llama-server.zip")

	var lastPct int = -1
	if err := models.DownloadFile(serverURL, zipPath, func(downloaded, total int64) {
		if progressFn != nil && total > 0 {
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
