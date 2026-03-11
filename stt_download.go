package main

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/whispaste/whispaste/internal/models"
)

const (
	sttServerRepo     = "ggml-org/whisper.cpp"
	sttServerAssetKey = "bin-x64"
)

// sttDownloadMu serializes STT downloads to prevent concurrent server binary extraction.
var sttDownloadMu sync.Mutex

// DownloadSTT downloads the whisper-server binary (if needed) and a GGML model.
// progressFn is called with phase ("server" or "model") and percentage (0–100).
func DownloadSTT(modelID string, progressFn func(phase string, pct int)) error {
	sttDownloadMu.Lock()
	defer sttDownloadMu.Unlock()
	model := models.Find(modelID)
	if model == nil {
		return fmt.Errorf("unknown STT model: %s", modelID)
	}

	dir, err := STTDir()
	if err != nil {
		return fmt.Errorf("stt dir: %w", err)
	}

	// Phase 1: Download and extract whisper-server ZIP (skip if already installed)
	if !IsSTTServerInstalled() {
		if progressFn != nil {
			progressFn("server", 0)
		}
		if err := downloadAndExtractSTTServer(dir, func(pct int) {
			if progressFn != nil {
				progressFn("server", pct)
			}
		}); err != nil {
			return fmt.Errorf("download whisper-server: %w", err)
		}
	} else {
		if progressFn != nil {
			progressFn("server", 100)
		}
	}

	// Phase 2: Download model GGML file
	if progressFn != nil {
		progressFn("model", 0)
	}
	modelDest := filepath.Join(dir, model.Filename)
	var lastPct int = -1
	if err := models.DownloadFile(model.URL, modelDest, func(downloaded, total int64) {
		if progressFn != nil {
			if total <= 0 {
				total = model.SizeBytes
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
		return fmt.Errorf("download stt model: %w", err)
	}

	// Verify SHA256 hash if specified
	if model.SHA256 != "" {
		if progressFn != nil {
			progressFn("verify", 0)
		}
		if err := models.VerifyFileHash(modelDest, model.SHA256); err != nil {
			os.Remove(modelDest)
			return fmt.Errorf("model hash verification failed: %w", err)
		}
		if progressFn != nil {
			progressFn("verify", 100)
		}
	}

	logInfo("STT download complete: %s", modelID)
	return nil
}

// resolveSTTServerURL queries the GitHub API for the latest whisper.cpp release
// and returns the download URL for the Windows x64 CPU asset.
func resolveSTTServerURL() (string, error) {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", sttServerRepo)
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

	// Look for CPU-only Windows x64 ZIP (e.g. "whisper-bin-x64.zip")
	for _, a := range release.Assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, sttServerAssetKey) &&
			strings.HasSuffix(name, ".zip") &&
			!strings.Contains(name, "cuda") &&
			!strings.Contains(name, "cublas") {
			return a.BrowserDownloadURL, nil
		}
	}

	// Fallback: look for any windows x64 zip
	for _, a := range release.Assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, "win") &&
			strings.Contains(name, "x64") &&
			strings.HasSuffix(name, ".zip") &&
			!strings.Contains(name, "cuda") {
			return a.BrowserDownloadURL, nil
		}
	}

	return "", fmt.Errorf("no matching asset (%s) found in latest release", sttServerAssetKey)
}

// downloadAndExtractSTTServer downloads the ZIP and extracts whisper-server.exe and DLLs.
func downloadAndExtractSTTServer(destDir string, progressFn func(pct int)) error {
	serverURL, err := resolveSTTServerURL()
	if err != nil {
		return fmt.Errorf("resolve server URL: %w", err)
	}
	logInfo("STT server download URL: %s", serverURL)

	zipPath := filepath.Join(destDir, "whisper-server.zip")

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
		return fmt.Errorf("download stt server: %w", err)
	}
	defer os.Remove(zipPath)

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("open zip: %w", err)
	}
	defer r.Close()

	for _, f := range r.File {
		baseName := filepath.Base(f.Name)
		// Extract whisper-server.exe (or server.exe) and any DLLs
		isRelevant := strings.EqualFold(baseName, "whisper-server.exe") ||
			strings.EqualFold(baseName, "server.exe") ||
			strings.HasSuffix(strings.ToLower(baseName), ".dll")
		if !isRelevant || f.FileInfo().IsDir() {
			continue
		}

		// Normalize server.exe → whisper-server.exe
		destName := baseName
		if strings.EqualFold(baseName, "server.exe") {
			destName = "whisper-server.exe"
		}

		destPath := filepath.Join(destDir, destName)
		// Zip Slip protection
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

// STTModelPath returns the full path to a model's GGML file.
func STTModelPath(modelID string) (string, error) {
	model := models.Find(modelID)
	if model == nil {
		return "", fmt.Errorf("unknown STT model: %s", modelID)
	}
	dir, err := STTDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, model.Filename), nil
}

// IsSTTModelInstalled checks if the GGML file for a specific model exists.
func IsSTTModelInstalled(modelID string) bool {
	model := models.Find(modelID)
	if model == nil {
		return false
	}
	dir, err := STTDir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, model.Filename))
	return err == nil
}

// DeleteSTTModel removes the GGML file for a specific model.
func DeleteSTTModel(modelID string) error {
	model := models.Find(modelID)
	if model == nil {
		return fmt.Errorf("unknown STT model: %s", modelID)
	}
	dir, err := STTDir()
	if err != nil {
		return fmt.Errorf("stt dir: %w", err)
	}
	modelPath := filepath.Join(dir, model.Filename)
	if err := os.Remove(modelPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("remove model: %w", err)
	}
	logInfo("STT model %s deleted", modelID)
	return nil
}

// DeleteSTT removes all STT files (server binary, models, DLLs).
func DeleteSTT() error {
	dir, err := STTDir()
	if err != nil {
		return fmt.Errorf("stt dir: %w", err)
	}
	if err := os.RemoveAll(dir); err != nil {
		return fmt.Errorf("remove stt dir: %w", err)
	}
	logInfo("STT files deleted")
	return nil
}

// migrateOldSTTModels removes old ONNX-format model directories that are incompatible.
func migrateOldSTTModels() {
	baseDir, err := models.Dir()
	if err != nil {
		return
	}
	for _, oldID := range []string{"whisper-base", "whisper-small"} {
		oldDir := filepath.Join(baseDir, oldID)
		// Check for old ONNX files (encoder/decoder pattern)
		if matches, _ := filepath.Glob(filepath.Join(oldDir, "*.onnx")); len(matches) > 0 {
			if err := os.RemoveAll(oldDir); err != nil {
				logWarn("Failed to remove old ONNX model dir %s: %v", oldDir, err)
			} else {
				logInfo("Removed old ONNX model directory: %s", oldDir)
			}
		}
	}
}
