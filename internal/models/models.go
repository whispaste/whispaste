package models

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
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
	ID              string // e.g. "whisper-base"
	Name            string // e.g. "Whisper Base"
	Size            string // human-readable size, e.g. "57MB"
	SizeBytes       int64  // approximate size in bytes (for progress)
	URL             string // direct download URL for the GGML file
	Filename        string // e.g. "ggml-base-q5_1.bin"
	SHA256          string // expected SHA256 hash (lowercase hex) from HuggingFace LFS
	MinRAMBytes     uint64 // minimum RAM for usable performance
	RecRAMBytes     uint64 // recommended RAM for good performance
	Quality         int    // 1-5 quality rating (1=lowest, 5=highest)
}

const (
	_GB = 1024 * 1024 * 1024
)

// Available lists all supported local Whisper models (GGML format), ordered by size.
var Available = []Info{
	{
		ID:          "whisper-tiny",
		Name:        "Whisper Tiny",
		Size:        "31MB",
		SizeBytes:   32_152_673,
		URL:         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin",
		Filename:    "ggml-tiny-q5_1.bin",
		SHA256:      "818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7",
		MinRAMBytes: 2 * _GB,
		RecRAMBytes: 4 * _GB,
		Quality:     1,
	},
	{
		ID:          "whisper-base",
		Name:        "Whisper Base",
		Size:        "57MB",
		SizeBytes:   59_700_000,
		URL:         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin",
		Filename:    "ggml-base-q5_1.bin",
		SHA256:      "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898",
		MinRAMBytes: 4 * _GB,
		RecRAMBytes: 4 * _GB,
		Quality:     2,
	},
	{
		ID:          "whisper-small",
		Name:        "Whisper Small",
		Size:        "181MB",
		SizeBytes:   190_085_487,
		URL:         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin",
		Filename:    "ggml-small-q5_1.bin",
		SHA256:      "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb",
		MinRAMBytes: 4 * _GB,
		RecRAMBytes: 8 * _GB,
		Quality:     3,
	},
	{
		ID:          "whisper-medium",
		Name:        "Whisper Medium",
		Size:        "514MB",
		SizeBytes:   539_212_467,
		URL:         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin",
		Filename:    "ggml-medium-q5_0.bin",
		SHA256:      "19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f",
		MinRAMBytes: 8 * _GB,
		RecRAMBytes: 16 * _GB,
		Quality:     4,
	},
	{
		ID:          "whisper-large-v3-turbo",
		Name:        "Whisper Large v3 Turbo",
		Size:        "547MB",
		SizeBytes:   574_041_195,
		URL:         "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
		Filename:    "ggml-large-v3-turbo-q5_0.bin",
		SHA256:      "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
		MinRAMBytes: 12 * _GB,
		RecRAMBytes: 16 * _GB,
		Quality:     5,
	},
}

// Recommend returns the best model ID for the given RAM in bytes.
func Recommend(ramBytes uint64) string {
	best := "whisper-base"
	for _, m := range Available {
		if ramBytes >= m.RecRAMBytes {
			best = m.ID
		}
	}
	return best
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
		DialContext:           (&net.Dialer{Timeout: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
		MaxIdleConnsPerHost:    4,
		IdleConnTimeout:        90 * time.Second,
		WriteBufferSize:        256 << 10,
		ReadBufferSize:         256 << 10,
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

	// Verify SHA256 hash if specified
	if model.SHA256 != "" {
		if err := VerifyFileHash(dest, model.SHA256); err != nil {
			os.Remove(dest)
			return fmt.Errorf("hash verification failed for %s: %w", model.Filename, err)
		}
	}

	return nil
}

// downloadIdleTimeout is the maximum time to wait for new data before aborting.
const downloadIdleTimeout = 60 * time.Second

// downloadMaxRetries is the number of retry attempts after a failed download.
const downloadMaxRetries = 3

// DownloadFile downloads a single file from url to dest, reporting progress.
// It retries up to downloadMaxRetries times on transient failures, attempting
// HTTP Range resume when the server supports it.
func DownloadFile(url, dest string, progressFn func(downloaded, total int64)) error {
	tmp := dest + ".tmp"
	var lastErr error

	for attempt := 0; attempt <= downloadMaxRetries; attempt++ {
		if attempt > 0 {
			backoff := time.Duration(attempt*attempt) * 5 * time.Second
			time.Sleep(backoff)
		}
		lastErr = downloadFileAttempt(url, tmp, progressFn)
		if lastErr == nil {
			break
		}
		// Only retry on network/stall errors, not on HTTP 4xx or disk errors
		if !isRetryableDownloadError(lastErr) {
			return lastErr
		}
	}
	if lastErr != nil {
		os.Remove(tmp)
		return lastErr
	}

	if err := os.Rename(tmp, dest); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("failed to rename temp file: %w", err)
	}
	return nil
}

func isRetryableDownloadError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	for _, substr := range []string{"stalled", "failed to read response", "connection", "timeout", "reset", "EOF"} {
		if containsCI(msg, substr) {
			return true
		}
	}
	return false
}

func containsCI(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		match := true
		for j := 0; j < len(sub); j++ {
			a, b := s[i+j], sub[j]
			if a >= 'A' && a <= 'Z' {
				a += 'a' - 'A'
			}
			if b >= 'A' && b <= 'Z' {
				b += 'a' - 'A'
			}
			if a != b {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}

// downloadFileAttempt performs a single download attempt, resuming from existing
// tmp file if the server supports HTTP Range requests.
func downloadFileAttempt(url, tmp string, progressFn func(downloaded, total int64)) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	idleTimer := time.AfterFunc(downloadIdleTimeout, cancel)
	defer idleTimer.Stop()

	// Check for existing partial download to resume
	var resumeOffset int64
	if fi, err := os.Stat(tmp); err == nil && fi.Size() > 0 {
		resumeOffset = fi.Size()
	}

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	if resumeOffset > 0 {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-", resumeOffset))
	}

	resp, err := modelHTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	var downloaded int64
	var total int64

	switch resp.StatusCode {
	case http.StatusOK:
		// Server doesn't support Range or sent full file — start from scratch
		resumeOffset = 0
		total = resp.ContentLength
	case http.StatusPartialContent:
		// Resume successful
		downloaded = resumeOffset
		if resp.ContentLength > 0 {
			total = resumeOffset + resp.ContentLength
		}
	default:
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	var f *os.File
	if resumeOffset > 0 && resp.StatusCode == http.StatusPartialContent {
		f, err = os.OpenFile(tmp, os.O_WRONLY|os.O_APPEND, 0o666)
	} else {
		f, err = os.Create(tmp)
	}
	if err != nil {
		return fmt.Errorf("failed to open temp file: %w", err)
	}

	bw := bufio.NewWriterSize(f, 256<<10) // 256 KB write buffer

	var lastReport int64
	buf := make([]byte, 256<<10) // 256 KB read buffer

	const progressInterval int64 = 256 << 10 // report every 256 KB

	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			idleTimer.Reset(downloadIdleTimeout)
			if _, wErr := bw.Write(buf[:n]); wErr != nil {
				bw.Flush()
				f.Close()
				return fmt.Errorf("failed to write file: %w", wErr)
			}
			downloaded += int64(n)
			if progressFn != nil && downloaded-lastReport >= progressInterval {
				lastReport = downloaded
				progressFn(downloaded, total)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			bw.Flush()
			f.Close()
			if ctx.Err() != nil {
				return fmt.Errorf("download stalled (no data received for %s)", downloadIdleTimeout)
			}
			return fmt.Errorf("failed to read response: %w", readErr)
		}
	}

	// Final progress report
	if progressFn != nil && downloaded != lastReport {
		progressFn(downloaded, total)
	}

	if err := bw.Flush(); err != nil {
		f.Close()
		return fmt.Errorf("failed to flush write buffer: %w", err)
	}

	if err := f.Close(); err != nil {
		return fmt.Errorf("failed to close temp file: %w", err)
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

// VerifyFileHash computes the SHA256 hash of a file and compares it to the expected value.
func VerifyFileHash(path, expectedHash string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("read file: %w", err)
	}

	actual := hex.EncodeToString(h.Sum(nil))
	if actual != expectedHash {
		return fmt.Errorf("SHA256 mismatch: expected %s, got %s", expectedHash, actual)
	}
	return nil
}
