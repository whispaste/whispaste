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

	"github.com/whispaste/whispaste/internal/gpu"
	"github.com/whispaste/whispaste/internal/models"
)

const (
	sttServerRepoUpstream  = "ggml-org/whisper.cpp"
	sttServerRepoWhisPaste = "whispaste/whispaste"
)

var fetchSTTReleaseAssets = fetchLatestSTTReleaseAssets
var gpuDetect = gpu.Detect
var gpuShouldUseRecommended = gpu.ShouldUseRecommendedGPU
var downloadAndExtractSTTServerFn = downloadAndExtractSTTServer

type sttAssetCandidate struct {
	Repo     string
	AssetKey string
	Backend  gpu.Backend
}

// sttAssetCandidates returns candidate release sources in priority order.
// The main WhisPaste release is preferred for bundled Vulkan/CUDA/CPU assets,
// then upstream whisper.cpp CPU/CUDA fallbacks remain as the safety net.
func sttAssetCandidates(gpuMode string) []sttAssetCandidate {
	if !gpuShouldUseRecommended(gpuMode) {
		return []sttAssetCandidate{
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-cpu-x64", Backend: gpu.BackendCPU},
			{Repo: sttServerRepoUpstream, AssetKey: "blas-bin-x64", Backend: gpu.BackendCPU},
		}
	}

	switch gpuDetect().Vendor {
	case gpu.VendorNVIDIA:
		return []sttAssetCandidate{
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-cuda12-x64", Backend: gpu.BackendCUDA},
			{Repo: sttServerRepoUpstream, AssetKey: "cublas-12", Backend: gpu.BackendCUDA},
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-cpu-x64", Backend: gpu.BackendCPU},
			{Repo: sttServerRepoUpstream, AssetKey: "blas-bin-x64", Backend: gpu.BackendCPU},
		}
	case gpu.VendorAMD, gpu.VendorIntel:
		return []sttAssetCandidate{
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-vulkan-x64", Backend: gpu.BackendVulkan},
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-cpu-x64", Backend: gpu.BackendCPU},
			{Repo: sttServerRepoUpstream, AssetKey: "blas-bin-x64", Backend: gpu.BackendCPU},
		}
	default:
		return []sttAssetCandidate{
			{Repo: sttServerRepoWhisPaste, AssetKey: "whisper-server-cpu-x64", Backend: gpu.BackendCPU},
			{Repo: sttServerRepoUpstream, AssetKey: "blas-bin-x64", Backend: gpu.BackendCPU},
		}
	}
}

// sttDownloadMu serializes STT downloads to prevent concurrent server binary extraction.
var sttDownloadMu sync.Mutex

// DownloadSTT downloads the whisper-server binary (if needed) and a GGML model.
// gpuMode controls asset selection: "auto" (detect), "enabled" (force CUDA), "disabled" (CPU only).
// progressFn is called with phase ("server" or "model") and percentage (0–100).
func DownloadSTT(modelID string, gpuMode string, progressFn func(phase string, pct int)) error {
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

	// Phase 1: Download and extract whisper-server ZIP (or refresh when backend type changed)
	needsServer := sttServerNeedsRefresh(dir, gpuMode)
	if needsServer {
		if progressFn != nil {
			progressFn("server", 0)
		}
		actualKey, err := downloadAndExtractSTTServerFn(dir, gpuMode, func(pct int) {
			if progressFn != nil {
				progressFn("server", pct)
			}
		})
		if err != nil {
			return fmt.Errorf("download whisper-server: %w", err)
		}
		writeSTTServerAssetKey(dir, actualKey)
		writeSTTServerRequestedKey(dir, sttRequestedAssetKey(gpuMode))
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

// ReleaseAsset represents a GitHub release asset with its name and download URL.
type ReleaseAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

func matchWhisPasteSTTAsset(assets []ReleaseAsset, assetKey string) (string, error) {
	for _, a := range assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, strings.ToLower(assetKey)) &&
			strings.Contains(name, "x64") &&
			strings.HasSuffix(name, ".zip") {
			return a.BrowserDownloadURL, nil
		}
	}
	return "", fmt.Errorf("no matching WhisPaste STT asset (%s) found in latest release", assetKey)
}

// matchSTTAsset selects the best matching asset URL from a list of release assets.
// WhisPaste-owned builds use explicit names; upstream whisper.cpp uses a 3-tier fallback strategy.
func matchSTTAsset(assets []ReleaseAsset, repo string, assetKey string) (string, error) {
	if repo == sttServerRepoWhisPaste {
		return matchWhisPasteSTTAsset(assets, assetKey)
	}

	// Primary: match exact asset key
	for _, a := range assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, assetKey) &&
			strings.Contains(name, "x64") &&
			strings.HasSuffix(name, ".zip") {
			return a.BrowserDownloadURL, nil
		}
	}

	// Fallback: OpenBLAS CPU build (always good performance)
	for _, a := range assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, "blas-bin-x64") &&
			strings.HasSuffix(name, ".zip") &&
			!strings.Contains(name, "cublas") {
			return a.BrowserDownloadURL, nil
		}
	}

	// Last resort: any x64 zip that isn't a CUDA build
	for _, a := range assets {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, "bin-x64") &&
			strings.HasSuffix(name, ".zip") &&
			!strings.Contains(name, "cublas") {
			return a.BrowserDownloadURL, nil
		}
	}

	return "", fmt.Errorf("no matching asset (%s) found in latest release", assetKey)
}

func fetchLatestSTTReleaseAssets(repo string) ([]ReleaseAsset, error) {
	apiURL := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo)
	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("GitHub API request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}

	var release struct {
		Assets []ReleaseAsset `json:"assets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return release.Assets, nil
}

func sttRequestedAssetKey(gpuMode string) string {
	candidates := sttAssetCandidates(gpuMode)
	if len(candidates) == 0 {
		return ""
	}
	return candidates[0].AssetKey
}

func sttServerNeedsRefresh(dir string, gpuMode string) bool {
	wantRequestedKey := sttRequestedAssetKey(gpuMode)
	return !IsSTTServerInstalled() ||
		sttServerRequestedKey(dir) != wantRequestedKey ||
		sttServerAssetKey(dir) == ""
}

func sttServerAssetKey(dir string) string {
	data, err := os.ReadFile(filepath.Join(dir, ".stt-asset-key"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func writeSTTServerAssetKey(dir string, key string) {
	if err := os.WriteFile(filepath.Join(dir, ".stt-asset-key"), []byte(key), 0600); err != nil {
		logWarn("Failed to write STT asset key marker: %v", err)
	}
}

func sttServerRequestedKey(dir string) string {
	data, err := os.ReadFile(filepath.Join(dir, ".stt-requested-key"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func writeSTTServerRequestedKey(dir string, key string) {
	if err := os.WriteFile(filepath.Join(dir, ".stt-requested-key"), []byte(key), 0600); err != nil {
		logWarn("Failed to write STT requested key marker: %v", err)
	}
}

// resolveSTTServerURL tries WhisPaste-owned STT artifacts first where relevant,
// then falls back to upstream whisper.cpp CPU/CUDA assets.
func resolveSTTServerURL(gpuMode string) (string, string, error) {
	candidates := sttAssetCandidates(gpuMode)
	var reasons []string
	for _, candidate := range candidates {
		assets, err := fetchSTTReleaseAssets(candidate.Repo)
		if err != nil {
			logWarn("STT release lookup failed for %s (%s): %v", candidate.Repo, candidate.Backend, err)
			reasons = append(reasons, fmt.Sprintf("%s: %v", candidate.Repo, err))
			continue
		}
		serverURL, err := matchSTTAsset(assets, candidate.Repo, candidate.AssetKey)
		if err != nil {
			logWarn("STT asset match failed for %s (%s): %v", candidate.Repo, candidate.AssetKey, err)
			reasons = append(reasons, fmt.Sprintf("%s/%s: %v", candidate.Repo, candidate.AssetKey, err))
			continue
		}
		return serverURL, candidate.AssetKey, nil
	}
	return "", "", fmt.Errorf("resolve STT server URL: %s", strings.Join(reasons, "; "))
}

func EnsureSTTServerRuntime(gpuMode string) error {
	dir, err := STTDir()
	if err != nil {
		return fmt.Errorf("stt dir: %w", err)
	}
	if !sttServerNeedsRefresh(dir, gpuMode) {
		return nil
	}
	actualKey, err := downloadAndExtractSTTServerFn(dir, gpuMode, nil)
	if err != nil {
		return fmt.Errorf("refresh stt runtime: %w", err)
	}
	writeSTTServerAssetKey(dir, actualKey)
	writeSTTServerRequestedKey(dir, sttRequestedAssetKey(gpuMode))
	logInfo("STT runtime refreshed: requested=%s actual=%s", sttRequestedAssetKey(gpuMode), actualKey)
	return nil
}

// downloadAndExtractSTTServer downloads the ZIP and extracts whisper-server.exe and DLLs.
func downloadAndExtractSTTServer(destDir string, gpuMode string, progressFn func(pct int)) (string, error) {
	serverURL, actualKey, err := resolveSTTServerURL(gpuMode)
	if err != nil {
		return "", fmt.Errorf("resolve server URL: %w", err)
	}
	logInfo("STT server download URL: %s", serverURL)

	zipPath := filepath.Join(destDir, "whisper-server.zip")

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
		return "", fmt.Errorf("download stt server: %w", err)
	}
	defer os.Remove(zipPath)

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return "", fmt.Errorf("open zip: %w", err)
	}
	defer r.Close()

	if err := cleanupSTTServerRuntimeFiles(destDir); err != nil {
		return "", fmt.Errorf("cleanup old STT runtime: %w", err)
	}

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
			return "", fmt.Errorf("extract %s: %w", baseName, err)
		}
	}

	return actualKey, nil
}

func cleanupSTTServerRuntimeFiles(destDir string) error {
	entries, err := os.ReadDir(destDir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := strings.ToLower(entry.Name())
		if name == "whisper-server.exe" || name == "server.exe" || strings.HasSuffix(name, ".dll") {
			if err := os.Remove(filepath.Join(destDir, entry.Name())); err != nil && !os.IsNotExist(err) {
				return err
			}
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
