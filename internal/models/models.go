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

// Info describes an available local Whisper model (single GGML file).
type Info struct {
	ID        string // e.g. "whisper-base"
	Name      string // e.g. "Whisper Base"
	Size      string // human-readable size, e.g. "57MB"
	SizeBytes int64  // approximate size in bytes (for progress)
	URL       string // direct download URL for the GGML file
	Filename  string // e.g. "ggml-base-q5_1.bin"
}

// Available lists all supported local Whisper models (GGML format).
var Available = []Info{
	{
		ID:        "whisper-base",
		Name:      "Whisper Base",
		Size:      "57MB",
		SizeBytes: 59_700_000,
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin",
		Filename:  "ggml-base-q5_1.bin",
	},
	{
		ID:        "whisper-small",
		Name:      "Whisper Small",
		Size:      "175MB",
		SizeBytes: 181_000_000,
		URL:       "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin",
		Filename:  "ggml-small-q5_1.bin",
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

// GetDir returns the directory for a specific model (stt/ subdirectory).
func GetDir(modelID string) (string, error) {
	base, err := Dir()
	if err != nil {
		return "", fmt.Errorf("failed to get models directory: %w", err)
	}
	return filepath.Join(base, "stt"), nil
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

// IsDownloaded checks whether the GGML model file exists on disk.
func IsDownloaded(modelID string) bool {
	model := Find(modelID)
	if model == nil {
		return false
	}
	dir, err := Dir()
	if err != nil {
		return false
	}
	sttDir := filepath.Join(dir, "stt")
	_, err = os.Stat(filepath.Join(sttDir, model.Filename))
	return err == nil
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

// Download downloads the GGML model file for the specified model.
func Download(modelID string, progressFn func(fileDownloaded, fileTotal int64, fileIdx, fileCount int, fileName string)) error {
	model := Find(modelID)
	if model == nil {
		return fmt.Errorf("unknown model: %s", modelID)
	}

	dir, err := Dir()
	if err != nil {
		return fmt.Errorf("failed to get models directory: %w", err)
	}
	sttDir := filepath.Join(dir, "stt")
	if err := os.MkdirAll(sttDir, 0700); err != nil {
		return fmt.Errorf("failed to create stt directory: %w", err)
	}

	dest := filepath.Join(sttDir, model.Filename)
	var lastPct int = -1

	if err := DownloadFile(model.URL, dest, func(downloaded, total int64) {
		if progressFn != nil {
			var pct int
			if total > 0 {
				pct = int(float64(downloaded) / float64(total) * 100)
				if pct > 100 {
					pct = 100
				}
			}
			if pct != lastPct {
				lastPct = pct
				progressFn(downloaded, total, 0, 1, model.Filename)
			}
		}
	}); err != nil {
		return fmt.Errorf("failed to download %s: %w", model.Filename, err)
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

// Delete removes the GGML model file and any old-format per-model directory.
func Delete(modelID string) error {
	model := Find(modelID)
	if model == nil {
		return fmt.Errorf("unknown model: %s", modelID)
	}

	dir, err := Dir()
	if err != nil {
		return fmt.Errorf("failed to get models directory: %w", err)
	}

	sttDir := filepath.Join(dir, "stt")
	filePath := filepath.Join(sttDir, model.Filename)
	if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete model file: %w", err)
	}

	// Clean up old-format per-model directory if it exists
	oldDir := filepath.Join(dir, modelID)
	if info, e := os.Stat(oldDir); e == nil && info.IsDir() {
		os.RemoveAll(oldDir)
	}

	return nil
}
