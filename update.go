package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	githubRepo          = "silvio-l/whispaste"
	releasesAPI         = "https://api.github.com/repos/" + githubRepo + "/releases/latest"
	updateCheckInterval = 6 * time.Hour
	minCheckInterval    = 1 * time.Hour
	downloadTimeout     = 60 * time.Second
)

var (
	storePackageOnce   sync.Once
	storePackageResult bool
)

// isStorePackage reports whether the app is running as an MSIX-packaged Store app.
// The result is cached after the first call.
func isStorePackage() bool {
	storePackageOnce.Do(func() {
		kernel32 := windows.NewLazySystemDLL("kernel32.dll")
		proc := kernel32.NewProc("GetCurrentPackageFullName")

		var length uint32
		ret, _, _ := proc.Call(uintptr(unsafe.Pointer(&length)), 0)

		const appmodelErrorNoPackage = 15700
		switch ret {
		case appmodelErrorNoPackage:
			storePackageResult = false
		case uintptr(windows.ERROR_INSUFFICIENT_BUFFER), uintptr(windows.ERROR_SUCCESS):
			storePackageResult = true
		default:
			storePackageResult = false
		}
	})
	return storePackageResult
}

// UpdateInfo holds information about an available update.
type UpdateInfo struct {
	Available   bool
	Version     string
	DownloadURL string
	ChecksumURL string
	ReleaseURL  string
}

// Updater checks for new releases on GitHub and applies updates.
type Updater struct {
	currentVersion string
	releasesURL    string // overridable for testing; defaults to releasesAPI
	checkEnabled   func() bool
	onAvailable    func(UpdateInfo)
	lastCheck      time.Time
	mu             sync.Mutex
	cancel         context.CancelFunc
	done           chan struct{}
	applying       atomic.Bool
	applyWg        sync.WaitGroup
}

// NewUpdater creates an updater that checks GitHub releases.
func NewUpdater(currentVersion string, checkEnabled func() bool) *Updater {
	return &Updater{
		currentVersion: currentVersion,
		releasesURL:    releasesAPI,
		checkEnabled:   checkEnabled,
		done:           make(chan struct{}),
	}
}

// OnUpdateAvailable registers a callback invoked when a newer version is found.
func (u *Updater) OnUpdateAvailable(fn func(UpdateInfo)) {
	u.mu.Lock()
	defer u.mu.Unlock()
	u.onAvailable = fn
}

// Start begins periodic update checks in the background.
func (u *Updater) Start(ctx context.Context) {
	ctx, u.cancel = context.WithCancel(ctx)
	go func() {
		defer close(u.done)
		// Delay initial check to not slow down app startup
		select {
		case <-time.After(5 * time.Second):
		case <-ctx.Done():
			return
		}
		u.checkAndNotify(ctx)
		ticker := time.NewTicker(updateCheckInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				u.checkAndNotify(ctx)
			case <-ctx.Done():
				return
			}
		}
	}()
}

// Stop cancels the background check loop and waits for it to finish.
// It also waits for any in-flight Apply operation to complete.
func (u *Updater) Stop() {
	if u.cancel != nil {
		u.cancel()
	}
	<-u.done
	u.applyWg.Wait()
}

func (u *Updater) checkAndNotify(ctx context.Context) {
	if isStorePackage() {
		logInfo("Running as Store package, skipping self-update check")
		return
	}
	if u.checkEnabled != nil && !u.checkEnabled() {
		return
	}
	info, err := u.CheckNow(ctx)
	if err != nil {
		logWarn("Update check failed: %v", err)
		return
	}
	if info.Available {
		u.mu.Lock()
		fn := u.onAvailable
		u.mu.Unlock()
		if fn != nil {
			fn(*info)
		}
	}
}

// CheckNow queries the GitHub releases API for a newer version.
// It rate-limits to at most one request per minCheckInterval.
// Pass force=true to bypass the rate limit (e.g. for manual user-initiated checks).
func (u *Updater) CheckNow(ctx context.Context, force ...bool) (*UpdateInfo, error) {
	bypass := len(force) > 0 && force[0]
	u.mu.Lock()
	if !bypass && time.Since(u.lastCheck) < minCheckInterval {
		u.mu.Unlock()
		return &UpdateInfo{Available: false}, nil
	}
	u.mu.Unlock()

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", u.releasesURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("User-Agent", "WhisPaste/"+u.currentVersion+" auto-updater")
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}

	// Only stamp lastCheck after a successful response
	u.mu.Lock()
	u.lastCheck = time.Now()
	u.mu.Unlock()

	var release struct {
		TagName string `json:"tag_name"`
		HTMLURL string `json:"html_url"`
		Assets  []struct {
			Name               string `json:"name"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	remoteVersion := strings.TrimPrefix(release.TagName, "v")
	if !isNewer(remoteVersion, u.currentVersion) {
		return &UpdateInfo{Available: false}, nil
	}

	info := &UpdateInfo{
		Available:  true,
		Version:    remoteVersion,
		ReleaseURL: release.HTMLURL,
	}
	for _, asset := range release.Assets {
		switch asset.Name {
		case "whispaste.exe":
			if !strings.HasPrefix(asset.BrowserDownloadURL, "https://") {
				return nil, fmt.Errorf("download URL is not HTTPS")
			}
			info.DownloadURL = asset.BrowserDownloadURL
		case "whispaste.exe.sha256":
			if !strings.HasPrefix(asset.BrowserDownloadURL, "https://") {
				return nil, fmt.Errorf("checksum URL is not HTTPS")
			}
			info.ChecksumURL = asset.BrowserDownloadURL
		}
	}
	if info.DownloadURL == "" || info.ChecksumURL == "" {
		return nil, fmt.Errorf("release assets missing (exe or checksum)")
	}
	return info, nil
}

// Apply downloads and replaces the current binary with the new version.
// It is safe to call from multiple goroutines — only one Apply runs at a time.
func (u *Updater) Apply(info *UpdateInfo) error {
	if info == nil || !info.Available {
		return fmt.Errorf("no update available")
	}
	if !u.applying.CompareAndSwap(false, true) {
		return fmt.Errorf("update already in progress")
	}
	u.applyWg.Add(1)
	defer func() {
		u.applying.Store(false)
		u.applyWg.Done()
	}()

	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("get exe path: %w", err)
	}
	exePath, err = filepath.EvalSymlinks(exePath)
	if err != nil {
		return fmt.Errorf("resolve exe path: %w", err)
	}

	dir := filepath.Dir(exePath)
	newPath := filepath.Join(dir, "whispaste.exe.new")
	oldPath := filepath.Join(dir, "whispaste.exe.old")

	// Clean up any leftover files from previous failed updates
	os.Remove(newPath)
	os.Remove(oldPath)

	// Download new binary
	ctx, cancel := context.WithTimeout(context.Background(), downloadTimeout)
	defer cancel()

	if err := downloadFile(ctx, info.DownloadURL, newPath, u.currentVersion); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("download failed: %w", err)
	}

	// Download and verify checksum
	expectedHash, err := downloadChecksum(ctx, info.ChecksumURL, u.currentVersion)
	if err != nil {
		os.Remove(newPath)
		return fmt.Errorf("checksum download failed: %w", err)
	}

	actualHash, err := fileSHA256(newPath)
	if err != nil {
		os.Remove(newPath)
		return fmt.Errorf("hash calculation failed: %w", err)
	}

	if !strings.EqualFold(actualHash, expectedHash) {
		os.Remove(newPath)
		return fmt.Errorf("checksum mismatch: expected %s, got %s", expectedHash, actualHash)
	}

	// Atomic replacement: current → .old, new → current
	if err := os.Rename(exePath, oldPath); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("backup current exe: %w", err)
	}
	if err := os.Rename(newPath, exePath); err != nil {
		// Rollback: restore old binary
		os.Rename(oldPath, exePath)
		return fmt.Errorf("replace exe: %w", err)
	}

	// Best-effort cleanup of old binary
	os.Remove(oldPath)

	logInfo("Update applied: %s → %s (restart to activate)", u.currentVersion, info.Version)
	return nil
}

// isNewer returns true if remote version is newer than current (simple semver).
func isNewer(remote, current string) bool {
	rParts := parseVersion(remote)
	cParts := parseVersion(current)
	for i := 0; i < 3; i++ {
		if rParts[i] > cParts[i] {
			return true
		}
		if rParts[i] < cParts[i] {
			return false
		}
	}
	return false
}

func parseVersion(v string) [3]int {
	v = strings.TrimPrefix(v, "v")
	var parts [3]int
	fmt.Sscanf(v, "%d.%d.%d", &parts[0], &parts[1], &parts[2])
	return parts
}

func downloadFile(ctx context.Context, url, dest, version string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "WhisPaste/"+version+" auto-updater")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = io.Copy(f, resp.Body)
	return err
}

func downloadChecksum(ctx context.Context, url, version string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "WhisPaste/"+version+" auto-updater")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 256))
	if err != nil {
		return "", err
	}

	// Format: "<hash>  <filename>" or just "<hash>"
	line := strings.TrimSpace(string(body))
	fields := strings.Fields(line)
	if len(fields) == 0 {
		return "", fmt.Errorf("empty checksum file")
	}
	hash := fields[0]
	if len(hash) != 64 {
		return "", fmt.Errorf("invalid SHA256 hash length: %d", len(hash))
	}
	return hash, nil
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
