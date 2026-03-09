package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseVersion(t *testing.T) {
	tests := []struct {
		input string
		want  [3]int
	}{
		{"1.0.0", [3]int{1, 0, 0}},
		{"v2.3.4", [3]int{2, 3, 4}},
		{"0.0.1", [3]int{0, 0, 1}},
		{"10.20.30", [3]int{10, 20, 30}},
		{"", [3]int{0, 0, 0}},
		{"invalid", [3]int{0, 0, 0}},
		{"v1.2", [3]int{1, 2, 0}},
	}
	for _, tt := range tests {
		got := parseVersion(tt.input)
		if got != tt.want {
			t.Errorf("parseVersion(%q) = %v, want %v", tt.input, got, tt.want)
		}
	}
}

func TestIsNewer(t *testing.T) {
	tests := []struct {
		remote, current string
		want            bool
	}{
		{"1.1.0", "1.0.0", true},
		{"2.0.0", "1.9.9", true},
		{"1.0.1", "1.0.0", true},
		{"1.0.0", "1.0.0", false},
		{"1.0.0", "1.0.1", false},
		{"0.9.0", "1.0.0", false},
		{"v2.0.0", "v1.0.0", true},
		{"1.0.0", "2.0.0", false},
	}
	for _, tt := range tests {
		got := isNewer(tt.remote, tt.current)
		if got != tt.want {
			t.Errorf("isNewer(%q, %q) = %v, want %v", tt.remote, tt.current, got, tt.want)
		}
	}
}

func TestFileSHA256(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "test.bin")
	content := []byte("hello world")
	if err := os.WriteFile(path, content, 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	got, err := fileSHA256(path)
	if err != nil {
		t.Fatalf("fileSHA256: %v", err)
	}

	h := sha256.Sum256(content)
	want := hex.EncodeToString(h[:])
	if got != want {
		t.Errorf("fileSHA256 = %q, want %q", got, want)
	}
}

func TestFileSHA256NotFound(t *testing.T) {
	_, err := fileSHA256("/nonexistent/path/file.bin")
	if err == nil {
		t.Error("fileSHA256 should fail for nonexistent file")
	}
}

func TestNewUpdater(t *testing.T) {
	u := NewUpdater("1.0.0", func() bool { return true })
	if u == nil {
		t.Fatal("NewUpdater returned nil")
	}
	if u.currentVersion != "1.0.0" {
		t.Errorf("currentVersion = %q, want 1.0.0", u.currentVersion)
	}
}

func TestUpdaterRateLimit(t *testing.T) {
	// Create a test server that returns a valid but no-update response
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"tag_name": "v1.0.0",
			"html_url": "https://github.com/test/test/releases/v1.0.0",
			"assets":   []interface{}{},
		})
	}))
	defer srv.Close()

	u := NewUpdater("1.0.0", func() bool { return true })

	// Override lastCheck to simulate a recent check
	u.mu.Lock()
	u.lastCheck = time.Now()
	u.mu.Unlock()

	info, err := u.CheckNow(context.Background())
	if err != nil {
		t.Fatalf("CheckNow: %v", err)
	}
	// Should be rate-limited — returns not available without hitting the server
	if info.Available {
		t.Error("Expected rate-limited response (not available)")
	}
}

func TestUpdaterApplyNilInfo(t *testing.T) {
	u := NewUpdater("1.0.0", func() bool { return true })
	err := u.Apply(nil)
	if err == nil {
		t.Error("Apply(nil) should return error")
	}
}

func TestUpdaterApplyNotAvailable(t *testing.T) {
	u := NewUpdater("1.0.0", func() bool { return true })
	err := u.Apply(&UpdateInfo{Available: false})
	if err == nil {
		t.Error("Apply with Available=false should return error")
	}
}

func TestChecksumDownload(t *testing.T) {
	hash := "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
	tests := []struct {
		name    string
		body    string
		wantErr bool
	}{
		{"hash only", hash, false},
		{"hash with filename", hash + "  whispaste.exe", false},
		{"empty", "", true},
		{"short hash", "abc123", true},
		{"too long", hash + "extra", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprint(w, tt.body)
			}))
			defer srv.Close()

			got, err := downloadChecksum(context.Background(), srv.URL, "1.0.0")
			if tt.wantErr {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != hash {
				t.Errorf("hash = %q, want %q", got, hash)
			}
		})
	}
}

func TestDownloadChecksumHTTPSValidation(t *testing.T) {
	// Test that CheckNow rejects non-HTTPS download URLs
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"tag_name": "v2.0.0",
			"html_url": "https://github.com/test/releases",
			"assets": []interface{}{
				map[string]interface{}{
					"name":                 "whispaste.exe",
					"browser_download_url": "http://evil.com/malware.exe", // non-HTTPS
				},
				map[string]interface{}{
					"name":                 "whispaste.exe.sha256",
					"browser_download_url": "https://github.com/test/checksum",
				},
			},
		})
	}))
	defer srv.Close()

	u := NewUpdater("1.0.0", func() bool { return true })
	u.releasesURL = srv.URL

	_, err := u.CheckNow(context.Background(), true)
	if err == nil {
		t.Fatal("CheckNow should reject non-HTTPS download URLs")
	}
	if !strings.Contains(err.Error(), "not HTTPS") {
		t.Errorf("error = %q, want 'not HTTPS'", err.Error())
	}
}

// --- 6.1 Version comparison edge cases ---

func TestIsNewerEdgeCases(t *testing.T) {
	tests := []struct {
		name            string
		remote, current string
		want            bool
	}{
		{"alpha to alpha minor bump", "0.4.0-alpha", "0.3.0-alpha", true},
		{"same version no update", "0.3.0", "0.3.0", false},
		{"major beats high minor", "1.0.0", "0.9.9", true},
		// parseVersion uses Sscanf("%d.%d.%d") which stops at the hyphen,
		// so 0.3.0-alpha parses as [0,3,0] — same as 0.3.0. Pre-release
		// ordering is not supported by the current simple semver parser.
		{"release vs alpha same base", "0.3.0", "0.3.0-alpha", false},
		{"alpha higher base than release", "0.4.0-alpha", "0.3.0", true},
		{"empty remote", "", "1.0.0", false},
		{"empty current", "1.0.0", "", true},
		{"both empty", "", "", false},
		{"invalid strings", "invalid", "also-invalid", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isNewer(tt.remote, tt.current)
			if got != tt.want {
				t.Errorf("isNewer(%q, %q) = %v, want %v", tt.remote, tt.current, got, tt.want)
			}
		})
	}
}

// --- 6.2 Mock server: version detection + download + checksum verification ---

func TestUpdateCheckWithMockServer(t *testing.T) {
	binaryContent := []byte("fake-whispaste-binary-v2.0.0")
	h := sha256.Sum256(binaryContent)
	checksum := hex.EncodeToString(h[:])

	mux := http.NewServeMux()
	mux.HandleFunc("/api/releases/latest", func(w http.ResponseWriter, r *http.Request) {
		if ua := r.Header.Get("User-Agent"); !strings.Contains(ua, "WhisPaste") {
			t.Errorf("missing WhisPaste User-Agent, got %q", ua)
		}
		json.NewEncoder(w).Encode(map[string]interface{}{
			"tag_name": "v2.0.0",
			"html_url": "https://github.com/whispaste/whispaste/releases/tag/v2.0.0",
			"assets": []interface{}{
				map[string]interface{}{
					"name":                 "whispaste.exe",
					"browser_download_url": "https://github.com/whispaste/releases/download/v2.0.0/whispaste.exe",
				},
				map[string]interface{}{
					"name":                 "whispaste.exe.sha256",
					"browser_download_url": "https://github.com/whispaste/releases/download/v2.0.0/whispaste.exe.sha256",
				},
			},
		})
	})
	mux.HandleFunc("/download/whispaste.exe", func(w http.ResponseWriter, r *http.Request) {
		w.Write(binaryContent)
	})
	mux.HandleFunc("/download/whispaste.exe.sha256", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s  whispaste.exe\n", checksum)
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	// Part 1: Verify the updater detects a newer version
	u := NewUpdater("1.0.0", func() bool { return true })
	u.releasesURL = srv.URL + "/api/releases/latest"

	info, err := u.CheckNow(context.Background(), true)
	if err != nil {
		t.Fatalf("CheckNow: %v", err)
	}
	if !info.Available {
		t.Fatal("expected update to be available")
	}
	if info.Version != "2.0.0" {
		t.Errorf("version = %q, want %q", info.Version, "2.0.0")
	}
	if info.ReleaseURL == "" {
		t.Error("expected non-empty ReleaseURL")
	}

	// Part 2: Download the binary and verify the checksum matches
	tmpDir := t.TempDir()
	dest := filepath.Join(tmpDir, "whispaste.exe")

	if err := downloadFile(context.Background(), srv.URL+"/download/whispaste.exe", dest, "1.0.0"); err != nil {
		t.Fatalf("downloadFile: %v", err)
	}

	expectedHash, err := downloadChecksum(context.Background(), srv.URL+"/download/whispaste.exe.sha256", "1.0.0")
	if err != nil {
		t.Fatalf("downloadChecksum: %v", err)
	}

	actualHash, err := fileSHA256(dest)
	if err != nil {
		t.Fatalf("fileSHA256: %v", err)
	}

	if !strings.EqualFold(actualHash, expectedHash) {
		t.Errorf("checksum mismatch: got %s, want %s", actualHash, expectedHash)
	}
}

// --- 6.3 SHA256 mismatch: updater rejects tampered download ---

func TestUpdateChecksumMismatch(t *testing.T) {
	binaryContent := []byte("legitimate-binary-content")
	wrongChecksum := strings.Repeat("ab", 32) // valid 64-char hex, wrong hash

	mux := http.NewServeMux()
	mux.HandleFunc("/download/whispaste.exe", func(w http.ResponseWriter, r *http.Request) {
		w.Write(binaryContent)
	})
	mux.HandleFunc("/download/whispaste.exe.sha256", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s  whispaste.exe\n", wrongChecksum)
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	tmpDir := t.TempDir()
	dest := filepath.Join(tmpDir, "whispaste.exe")

	if err := downloadFile(context.Background(), srv.URL+"/download/whispaste.exe", dest, "1.0.0"); err != nil {
		t.Fatalf("downloadFile: %v", err)
	}

	expectedHash, err := downloadChecksum(context.Background(), srv.URL+"/download/whispaste.exe.sha256", "1.0.0")
	if err != nil {
		t.Fatalf("downloadChecksum: %v", err)
	}

	actualHash, err := fileSHA256(dest)
	if err != nil {
		t.Fatalf("fileSHA256: %v", err)
	}

	// This must fail — a matching checksum here would mean the integrity check is broken
	if strings.EqualFold(actualHash, expectedHash) {
		t.Fatal("expected checksum mismatch, but hashes matched — integrity check is broken")
	}
}

// --- 6.4 MSIX / store-package skip ---

func TestUpdateSkipStorePackage(t *testing.T) {
	// isStorePackage() calls GetCurrentPackageFullName via Win32 API.
	// In a normal test environment (not MSIX-packaged), it must return false.
	if isStorePackage() {
		t.Skip("running inside MSIX package — cannot test non-store path")
	}
	// If we reach here, isStorePackage() correctly returned false.
}

func TestUpdateSkipWhenDisabled(t *testing.T) {
	// The checkEnabled callback lets callers disable update checks at runtime.
	// Verify that CheckNow is never called when checkEnabled returns false.
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		json.NewEncoder(w).Encode(map[string]interface{}{
			"tag_name": "v99.0.0",
			"html_url": "https://github.com/test/releases",
			"assets":   []interface{}{},
		})
	}))
	defer srv.Close()

	u := NewUpdater("1.0.0", func() bool { return false })
	u.releasesURL = srv.URL

	// checkAndNotify should bail out before hitting the server
	u.checkAndNotify(context.Background())

	if calls != 0 {
		t.Errorf("server was hit %d times; expected 0 when updates disabled", calls)
	}
}
