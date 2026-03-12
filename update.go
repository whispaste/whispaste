package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
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
	githubRepo          = "whispaste/whispaste"
	releasesAPI         = "https://api.github.com/repos/" + githubRepo + "/releases?per_page=10"
	updateCheckInterval = 6 * time.Hour
	minCheckInterval    = 1 * time.Hour
	downloadTimeout     = 60 * time.Second
)

// parsedVersion represents a parsed semantic version with pre-release info.
type parsedVersion struct {
	Major, Minor, Patch int
	PreRelease          int // 4=release, 3=rc, 2=beta, 1=alpha, 0=unknown/empty
}

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
	resolveExePath func() (string, error)
	replaceBinary  func(exePath, stagedPath string) error
	launchElevated func(stagedPath, exePath string, pid int) error
}

// NewUpdater creates an updater that checks GitHub releases.
func NewUpdater(currentVersion string, checkEnabled func() bool) *Updater {
	return &Updater{
		currentVersion: currentVersion,
		releasesURL:    releasesAPI,
		checkEnabled:   checkEnabled,
		done:           make(chan struct{}),
		resolveExePath: currentExecutablePath,
		replaceBinary:  replaceBinaryInPlace,
		launchElevated: launchElevatedUpdateHelper,
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
		logDebug("Update check skipped: updates disabled by user setting")
		return
	}
	info, err := u.CheckNow(ctx)
	if err != nil {
		logWarn("Update check failed: %v", err)
		return
	}
	if info.Available {
		logInfo("Update available: %s → %s", u.currentVersion, info.Version)
		u.mu.Lock()
		fn := u.onAvailable
		u.mu.Unlock()
		if fn != nil {
			fn(*info)
		}
	} else {
		logDebug("Update check: %s is up to date", u.currentVersion)
	}
}

// CheckNow queries the GitHub releases API for a newer version.
// It fetches the 10 most recent releases (including prereleases) and picks the
// highest version that is not a draft. This ensures pre-release versions like
// beta and rc are also detected, unlike the /releases/latest endpoint which
// only returns stable releases.
// Pass force=true to bypass the rate limit (e.g. for manual user-initiated checks).
func (u *Updater) CheckNow(ctx context.Context, force ...bool) (*UpdateInfo, error) {
	bypass := len(force) > 0 && force[0]
	u.mu.Lock()
	if !bypass && time.Since(u.lastCheck) < minCheckInterval {
		u.mu.Unlock()
		logDebug("Update check skipped (rate-limited, last check %s ago)", time.Since(u.lastCheck).Round(time.Second))
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

	type releaseAsset struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	}
	type githubRelease struct {
		TagName string         `json:"tag_name"`
		HTMLURL string         `json:"html_url"`
		Draft   bool           `json:"draft"`
		Assets  []releaseAsset `json:"assets"`
	}

	var releases []githubRelease
	if err := json.NewDecoder(resp.Body).Decode(&releases); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}

	// Find the release with the highest version number (skip drafts)
	var best *githubRelease
	var bestVer parsedVersion
	for i := range releases {
		r := &releases[i]
		if r.Draft {
			continue
		}
		ver := parseVersion(r.TagName)
		if best == nil || compareVersions(ver, bestVer) > 0 {
			best = r
			bestVer = ver
		}
	}

	if best == nil {
		logDebug("Update check: no non-draft releases found")
		return &UpdateInfo{Available: false}, nil
	}

	remoteVersion := strings.TrimPrefix(best.TagName, "v")
	if !isNewer(remoteVersion, u.currentVersion) {
		return &UpdateInfo{Available: false}, nil
	}

	info := &UpdateInfo{
		Available:  true,
		Version:    remoteVersion,
		ReleaseURL: best.HTMLURL,
	}
	for _, asset := range best.Assets {
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

	exePath, err := u.resolveExePath()
	if err != nil {
		return fmt.Errorf("resolve exe path: %w", err)
	}

	stagedPath, err := newStagedUpdatePath()
	if err != nil {
		return fmt.Errorf("create staged update path: %w", err)
	}
	keepStaged := false
	defer func() {
		if !keepStaged {
			os.Remove(stagedPath)
		}
	}()

	// Download new binary
	ctx, cancel := context.WithTimeout(context.Background(), downloadTimeout)
	defer cancel()

	if err := downloadFile(ctx, info.DownloadURL, stagedPath, u.currentVersion); err != nil {
		return fmt.Errorf("download failed: %w", err)
	}

	// Download and verify checksum
	expectedHash, err := downloadChecksum(ctx, info.ChecksumURL, u.currentVersion)
	if err != nil {
		return fmt.Errorf("checksum download failed: %w", err)
	}

	actualHash, err := fileSHA256(stagedPath)
	if err != nil {
		return fmt.Errorf("hash calculation failed: %w", err)
	}

	if !strings.EqualFold(actualHash, expectedHash) {
		return fmt.Errorf("checksum mismatch: expected %s, got %s", expectedHash, actualHash)
	}

	if err := u.replaceBinary(exePath, stagedPath); err != nil {
		if !isUpdateAccessError(err) {
			return fmt.Errorf("replace exe: %w", err)
		}
		if err := u.launchElevated(stagedPath, exePath, os.Getpid()); err != nil {
			return fmt.Errorf("launch elevated updater: %w", err)
		}
		keepStaged = true
		logInfo("Update staged for elevated apply: %s → %s", u.currentVersion, info.Version)
		return nil
	}

	logInfo("Update applied: %s → %s (restart to activate)", u.currentVersion, info.Version)
	return nil
}

func currentExecutablePath() (string, error) {
	exePath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("get exe path: %w", err)
	}
	exePath, err = filepath.EvalSymlinks(exePath)
	if err != nil {
		return "", fmt.Errorf("resolve exe path: %w", err)
	}
	return exePath, nil
}

func newStagedUpdatePath() (string, error) {
	f, err := os.CreateTemp("", "whispaste-update-*.exe")
	if err != nil {
		return "", err
	}
	path := f.Name()
	if err := f.Close(); err != nil {
		os.Remove(path)
		return "", err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	return path, nil
}

func replaceBinaryInPlace(exePath, stagedPath string) error {
	dir := filepath.Dir(exePath)
	newPath := filepath.Join(dir, "whispaste.exe.new")
	oldPath := filepath.Join(dir, "whispaste.exe.old")

	os.Remove(newPath)
	os.Remove(oldPath)

	if err := copyFile(stagedPath, newPath); err != nil {
		return fmt.Errorf("stage new exe: %w", err)
	}
	if err := os.Rename(exePath, oldPath); err != nil {
		os.Remove(newPath)
		return fmt.Errorf("backup current exe: %w", err)
	}
	if err := os.Rename(newPath, exePath); err != nil {
		os.Rename(oldPath, exePath)
		return fmt.Errorf("replace exe: %w", err)
	}

	os.Remove(oldPath)
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}

	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func isUpdateAccessError(err error) bool {
	return errors.Is(err, os.ErrPermission) ||
		errors.Is(err, windows.ERROR_ACCESS_DENIED) ||
		errors.Is(err, windows.ERROR_SHARING_VIOLATION) ||
		errors.Is(err, windows.ERROR_PRIVILEGE_NOT_HELD)
}

func launchElevatedUpdateHelper(stagedPath, exePath string, pid int) error {
	scriptPath, err := writeElevatedUpdateScript(stagedPath, exePath, pid)
	if err != nil {
		return err
	}

	shell32 := windows.NewLazySystemDLL("shell32.dll")
	proc := shell32.NewProc("ShellExecuteW")

	verb, err := windows.UTF16PtrFromString("runas")
	if err != nil {
		return err
	}
	file, err := windows.UTF16PtrFromString("powershell.exe")
	if err != nil {
		return err
	}
	params, err := windows.UTF16PtrFromString(`-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "` + scriptPath + `"`)
	if err != nil {
		return err
	}

	ret, _, callErr := proc.Call(
		0,
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(file)),
		uintptr(unsafe.Pointer(params)),
		0,
		0,
	)
	if ret <= 32 {
		os.Remove(scriptPath)
		return fmt.Errorf("ShellExecuteW returned %d: %v", ret, callErr)
	}
	return nil
}

func writeElevatedUpdateScript(stagedPath, exePath string, pid int) (string, error) {
	f, err := os.CreateTemp("", "whispaste-update-*.ps1")
	if err != nil {
		return "", err
	}
	path := f.Name()
	if err := f.Close(); err != nil {
		os.Remove(path)
		return "", err
	}

	script := fmt.Sprintf(`$ErrorActionPreference = 'Stop'
$exePath = %s
$stagedPath = %s
$newPath = Join-Path (Split-Path -Parent $exePath) 'whispaste.exe.new'
$oldPath = Join-Path (Split-Path -Parent $exePath) 'whispaste.exe.old'
$targetPid = %d

Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 100; $i++) {
    if (-not (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)) {
        break
    }
    Start-Sleep -Milliseconds 100
}

if (Get-Process -Id $targetPid -ErrorAction SilentlyContinue) {
    throw 'update helper: process did not exit'
}

Remove-Item -LiteralPath $newPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath $stagedPath -Destination $newPath -Force
Move-Item -LiteralPath $exePath -Destination $oldPath -Force

try {
    Move-Item -LiteralPath $newPath -Destination $exePath -Force
} catch {
    Move-Item -LiteralPath $oldPath -Destination $exePath -Force
    throw
}

Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stagedPath -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $exePath
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
`, quotePowerShellLiteral(exePath), quotePowerShellLiteral(stagedPath), pid)

	if err := os.WriteFile(path, []byte(script), 0600); err != nil {
		os.Remove(path)
		return "", err
	}
	return path, nil
}

func quotePowerShellLiteral(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// isNewer returns true if remote version is newer than current.
// Supports pre-release labels: alpha < beta < rc < release.
func isNewer(remote, current string) bool {
	return compareVersions(parseVersion(remote), parseVersion(current)) > 0
}

// compareVersions returns >0 if a > b, 0 if a == b, <0 if a < b.
func compareVersions(a, b parsedVersion) int {
	if a.Major != b.Major {
		return a.Major - b.Major
	}
	if a.Minor != b.Minor {
		return a.Minor - b.Minor
	}
	if a.Patch != b.Patch {
		return a.Patch - b.Patch
	}
	return a.PreRelease - b.PreRelease
}

func parseVersion(v string) parsedVersion {
	v = strings.TrimPrefix(v, "v")
	if v == "" {
		return parsedVersion{}
	}

	var pv parsedVersion

	// Split on first hyphen to separate "1.0.0" from "beta"
	base := v
	suffix := ""
	if idx := strings.Index(v, "-"); idx >= 0 {
		base = v[:idx]
		suffix = strings.ToLower(v[idx+1:])
	}

	n, _ := fmt.Sscanf(base, "%d.%d.%d", &pv.Major, &pv.Minor, &pv.Patch)
	if n == 0 {
		return parsedVersion{} // not a valid version string
	}

	// Pre-release ordering (higher = newer)
	switch {
	case suffix == "":
		pv.PreRelease = 4 // stable release
	case strings.HasPrefix(suffix, "rc"):
		pv.PreRelease = 3
	case strings.HasPrefix(suffix, "beta"):
		pv.PreRelease = 2
	case strings.HasPrefix(suffix, "alpha"):
		pv.PreRelease = 1
	default:
		pv.PreRelease = 1 // unknown pre-release treated as alpha
	}

	return pv
}

func downloadFile(ctx context.Context, url, dest, version string) error {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("downloadFile: create request: %w", err)
	}
	req.Header.Set("User-Agent", "WhisPaste/"+version+" auto-updater")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("downloadFile: execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("downloadFile: HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(dest)
	if err != nil {
		return fmt.Errorf("downloadFile: create file: %w", err)
	}
	defer f.Close()

	if _, err = io.Copy(f, resp.Body); err != nil {
		return fmt.Errorf("downloadFile: write file: %w", err)
	}
	return nil
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
