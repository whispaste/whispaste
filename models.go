package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
)

// ModelInfo describes an available local Whisper model.
type ModelInfo struct {
	ID      string   // e.g. "whisper-tiny"
	Name    string   // e.g. "Whisper Tiny"
	Size    string   // human-readable size, e.g. "39MB"
	BaseURL string   // HuggingFace base URL for direct file downloads
	Files   []string // file names to download (encoder, decoder, tokens)
}

// AvailableModels lists all supported local Whisper models.
var AvailableModels = []ModelInfo{
	{
		ID:      "whisper-tiny",
		Name:    "Whisper Tiny",
		Size:    "39MB",
		BaseURL: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main",
		Files:   []string{"tiny-encoder.onnx", "tiny-decoder.onnx", "tiny-tokens.txt"},
	},
	{
		ID:      "whisper-base",
		Name:    "Whisper Base",
		Size:    "74MB",
		BaseURL: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main",
		Files:   []string{"base-encoder.onnx", "base-decoder.onnx", "base-tokens.txt"},
	},
	{
		ID:      "whisper-small",
		Name:    "Whisper Small",
		Size:    "244MB",
		BaseURL: "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main",
		Files:   []string{"small-encoder.onnx", "small-decoder.onnx", "small-tokens.txt"},
	},
}

// ModelsDir returns the directory where local models are stored.
// Creates the directory if it does not exist.
func ModelsDir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, AppName, "models")
	return dir, os.MkdirAll(dir, 0700)
}

// GetModelDir returns the directory for a specific model.
func GetModelDir(modelID string) (string, error) {
	base, err := ModelsDir()
	if err != nil {
		return "", fmt.Errorf("failed to get models directory: %w", err)
	}
	return filepath.Join(base, modelID), nil
}

// findModel returns the ModelInfo for the given ID, or nil if not found.
func findModel(modelID string) *ModelInfo {
	for i := range AvailableModels {
		if AvailableModels[i].ID == modelID {
			return &AvailableModels[i]
		}
	}
	return nil
}

// IsModelDownloaded checks whether all required files for a model exist on disk.
func IsModelDownloaded(modelID string) bool {
	model := findModel(modelID)
	if model == nil {
		return false
	}
	dir, err := GetModelDir(modelID)
	if err != nil {
		return false
	}
	for _, f := range model.Files {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			return false
		}
	}
	return true
}

// ListDownloadedModels returns all models that are fully downloaded.
func ListDownloadedModels() []ModelInfo {
	var result []ModelInfo
	for _, m := range AvailableModels {
		if IsModelDownloaded(m.ID) {
			result = append(result, m)
		}
	}
	return result
}

// DownloadModel downloads all files for the specified model.
// progressFn is called with bytes downloaded and total bytes (0 if unknown) for each file.
func DownloadModel(modelID string, progressFn func(downloaded, total int64)) error {
	model := findModel(modelID)
	if model == nil {
		return fmt.Errorf("unknown model: %s", modelID)
	}

	dir, err := GetModelDir(modelID)
	if err != nil {
		return fmt.Errorf("failed to get model directory: %w", err)
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("failed to create model directory: %w", err)
	}

	for _, fname := range model.Files {
		url := model.BaseURL + "/" + fname
		dest := filepath.Join(dir, fname)

		if err := downloadModelFile(url, dest, progressFn); err != nil {
			return fmt.Errorf("failed to download %s: %w", fname, err)
		}
		logInfo("downloaded model file: %s", fname)
	}

	return nil
}

// downloadModelFile downloads a single file from url to dest, reporting progress.
func downloadModelFile(url, dest string, progressFn func(downloaded, total int64)) error {
	resp, err := http.Get(url)
	if err != nil {
		return fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	// Write to a temp file first, then rename for atomicity.
	tmp := dest + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return fmt.Errorf("failed to create temp file: %w", err)
	}

	var downloaded int64
	total := resp.ContentLength
	buf := make([]byte, 32*1024)

	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			if _, wErr := f.Write(buf[:n]); wErr != nil {
				f.Close()
				os.Remove(tmp)
				return fmt.Errorf("failed to write file: %w", wErr)
			}
			downloaded += int64(n)
			if progressFn != nil {
				progressFn(downloaded, total)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			f.Close()
			os.Remove(tmp)
			return fmt.Errorf("failed to read response: %w", readErr)
		}
	}

	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("failed to close temp file: %w", err)
	}

	if err := os.Rename(tmp, dest); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("failed to rename temp file: %w", err)
	}

	return nil
}

// DeleteModel removes all files for a downloaded model.
func DeleteModel(modelID string) error {
	dir, err := GetModelDir(modelID)
	if err != nil {
		return fmt.Errorf("failed to get model directory: %w", err)
	}
	if err := os.RemoveAll(dir); err != nil {
		return fmt.Errorf("failed to delete model directory: %w", err)
	}
	logInfo("deleted model: %s", modelID)
	return nil
}
