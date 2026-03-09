package models

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

var appName string

// Init sets the app name used for directory paths.
func Init(name string) {
	appName = name
}

// Info describes an available local Whisper model.
type Info struct {
	ID        string   // e.g. "whisper-tiny"
	Name      string   // e.g. "Whisper Tiny"
	Size      string   // human-readable size, e.g. "39MB"
	SizeBytes int64    // approximate total size in bytes (for progress)
	BaseURL   string   // HuggingFace base URL for direct file downloads
	Files     []string // file names to download (encoder, decoder, tokens)
}

// Available lists all supported local Whisper models.
var Available = []Info{
	{
		ID:        "whisper-base",
		Name:      "Whisper Base",
		Size:      "74MB",
		SizeBytes: 77_594_624,
		BaseURL:   "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/main",
		Files:     []string{"base-encoder.onnx", "base-decoder.onnx", "base-tokens.txt"},
	},
	{
		ID:        "whisper-small",
		Name:      "Whisper Small",
		Size:      "244MB",
		SizeBytes: 255_852_544,
		BaseURL:   "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/main",
		Files:     []string{"small-encoder.onnx", "small-decoder.onnx", "small-tokens.txt"},
	},
}

// Dir returns the directory where local models are stored.
func Dir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, appName, "models")
	return dir, os.MkdirAll(dir, 0700)
}

// GetDir returns the directory for a specific model.
func GetDir(modelID string) (string, error) {
	base, err := Dir()
	if err != nil {
		return "", fmt.Errorf("failed to get models directory: %w", err)
	}
	return filepath.Join(base, modelID), nil
}

// Find returns the Info for the given ID, or nil if not found.
func Find(modelID string) *Info {
	for i := range Available {
		if Available[i].ID == modelID {
			return &Available[i]
		}
	}
	return nil
}

// IsDownloaded checks whether all required files for a model exist on disk.
func IsDownloaded(modelID string) bool {
	model := Find(modelID)
	if model == nil {
		return false
	}
	dir, err := GetDir(modelID)
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

// ListDownloaded returns all models that are fully downloaded.
func ListDownloaded() []Info {
	var result []Info
	for _, m := range Available {
		if IsDownloaded(m.ID) {
			result = append(result, m)
		}
	}
	return result
}

var modelHTTPClient = &http.Client{
	Transport: &http.Transport{
		DialContext:            (&net.Dialer{Timeout: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
	},
}

// Download downloads all files for the specified model.
func Download(modelID string, progressFn func(fileDownloaded, fileTotal int64, fileIdx, fileCount int, fileName string)) error {
	model := Find(modelID)
	if model == nil {
		return fmt.Errorf("unknown model: %s", modelID)
	}

	dir, err := GetDir(modelID)
	if err != nil {
		return fmt.Errorf("failed to get model directory: %w", err)
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("failed to create model directory: %w", err)
	}

	fileCount := len(model.Files)
	var lastPct int = -1
	var lastFileIdx int = -1

	for i, fname := range model.Files {
		url := model.BaseURL + "/" + fname
		dest := filepath.Join(dir, fname)

		if err := DownloadFile(url, dest, func(downloaded, total int64) {
			if progressFn != nil {
				var pct int
				if total > 0 {
					pct = int(float64(downloaded) / float64(total) * 100)
					if pct > 100 {
						pct = 100
					}
				}
				if pct != lastPct || i != lastFileIdx {
					lastPct = pct
					lastFileIdx = i
					progressFn(downloaded, total, i, fileCount, fname)
				}
			}
		}); err != nil {
			return fmt.Errorf("failed to download %s: %w", fname, err)
		}
	}

	return nil
}

// DownloadFile downloads a single file from url to dest, reporting progress.
func DownloadFile(url, dest string, progressFn func(downloaded, total int64)) error {
	resp, err := modelHTTPClient.Get(url)
	if err != nil {
		return fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

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

// Delete removes all files for a downloaded model.
func Delete(modelID string) error {
	dir, err := GetDir(modelID)
	if err != nil {
		return fmt.Errorf("failed to get model directory: %w", err)
	}
	if err := os.RemoveAll(dir); err != nil {
		return fmt.Errorf("failed to delete model directory: %w", err)
	}
	return nil
}
