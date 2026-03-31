package models

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFind(t *testing.T) {
	tests := []struct {
		name    string
		id      string
		wantNil bool
		wantID  string
	}{
		{name: "known model whisper-small", id: "whisper-small", wantNil: false, wantID: "whisper-small"},
		{name: "known model whisper-tiny", id: "whisper-tiny", wantNil: false, wantID: "whisper-tiny"},
		{name: "unknown model", id: "whisper-nonexistent", wantNil: true},
		{name: "empty string", id: "", wantNil: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Find(tt.id)
			if tt.wantNil {
				if got != nil {
					t.Errorf("Find(%q) = %+v, want nil", tt.id, got)
				}
				return
			}
			if got == nil {
				t.Fatalf("Find(%q) = nil, want non-nil", tt.id)
			}
			if got.ID != tt.wantID {
				t.Errorf("Find(%q).ID = %q, want %q", tt.id, got.ID, tt.wantID)
			}
			if got.Name == "" {
				t.Errorf("Find(%q).Name is empty", tt.id)
			}
			if got.Filename == "" {
				t.Errorf("Find(%q).Filename is empty", tt.id)
			}
			if got.SHA256 == "" {
				t.Errorf("Find(%q).SHA256 is empty", tt.id)
			}
		})
	}
}

func TestFindReturnsPointerIntoAvailable(t *testing.T) {
	info := Find("whisper-base")
	if info == nil {
		t.Fatal("Find(whisper-base) returned nil")
	}
	found := false
	for i := range Available {
		if info == &Available[i] {
			found = true
			break
		}
	}
	if !found {
		t.Error("Find should return a pointer into the Available slice, not a copy")
	}
}

func TestRecommend(t *testing.T) {
	tests := []struct {
		name     string
		ramBytes uint64
		wantID   string
	}{
		{name: "zero RAM falls back to default", ramBytes: 0, wantID: "whisper-base"},
		{name: "1 GB below all RecRAM", ramBytes: 1 * _GB, wantID: "whisper-base"},
		{name: "4 GB matches tiny+base RecRAM", ramBytes: 4 * _GB, wantID: "whisper-base"},
		{name: "8 GB matches small RecRAM", ramBytes: 8 * _GB, wantID: "whisper-small"},
		{name: "16 GB matches medium+turbo RecRAM", ramBytes: 16 * _GB, wantID: "whisper-large-v3-turbo"},
		{name: "32 GB exceeds all RecRAM", ramBytes: 32 * _GB, wantID: "whisper-large-v3-turbo"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Recommend(tt.ramBytes)
			if got != tt.wantID {
				t.Errorf("Recommend(%d) = %q, want %q", tt.ramBytes, got, tt.wantID)
			}
		})
	}
}

func TestRecommendModelFitsRAM(t *testing.T) {
	ramValues := []uint64{4 * _GB, 8 * _GB, 16 * _GB, 32 * _GB}
	for _, ram := range ramValues {
		id := Recommend(ram)
		info := Find(id)
		if info == nil {
			t.Fatalf("Recommend(%d) returned %q which Find cannot resolve", ram, id)
		}
		if info.RecRAMBytes > ram {
			t.Errorf("Recommend(%d) = %q (RecRAMBytes=%d), recommended model exceeds provided RAM",
				ram, id, info.RecRAMBytes)
		}
	}
}

func TestAvailableModels(t *testing.T) {
	if len(Available) == 0 {
		t.Fatal("Available slice is empty")
	}

	for _, m := range Available {
		t.Run(m.ID, func(t *testing.T) {
			if m.ID == "" {
				t.Error("ID is empty")
			}
			if m.Name == "" {
				t.Error("Name is empty")
			}
			if m.Filename == "" {
				t.Error("Filename is empty")
			}
			if m.SHA256 == "" {
				t.Error("SHA256 is empty")
			}
			if len(m.SHA256) != 64 {
				t.Errorf("SHA256 length = %d, want 64 hex chars", len(m.SHA256))
			}
			if m.SizeBytes <= 0 {
				t.Errorf("SizeBytes = %d, want > 0", m.SizeBytes)
			}
			if m.MinRAMBytes == 0 {
				t.Error("MinRAMBytes is 0")
			}
			if m.RecRAMBytes < m.MinRAMBytes {
				t.Errorf("RecRAMBytes (%d) < MinRAMBytes (%d)", m.RecRAMBytes, m.MinRAMBytes)
			}
			if m.Quality < 1 || m.Quality > 5 {
				t.Errorf("Quality = %d, want 1-5", m.Quality)
			}
			if m.URL == "" {
				t.Error("URL is empty")
			}
			if m.Size == "" {
				t.Error("Size is empty")
			}
		})
	}
}

func TestAvailableOrderedBySize(t *testing.T) {
	for i := 1; i < len(Available); i++ {
		if Available[i].SizeBytes < Available[i-1].SizeBytes {
			t.Errorf("Available not ordered by size: %s (%d bytes) comes after %s (%d bytes)",
				Available[i].ID, Available[i].SizeBytes,
				Available[i-1].ID, Available[i-1].SizeBytes)
		}
	}
}

func TestVerifyFileHash(t *testing.T) {
	content := []byte("WhisPaste test content for hashing")
	hash := sha256.Sum256(content)
	expectedHash := hex.EncodeToString(hash[:])

	t.Run("matching hash", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "testfile.bin")
		if err := os.WriteFile(path, content, 0644); err != nil {
			t.Fatalf("failed to write test file: %v", err)
		}
		if err := VerifyFileHash(path, expectedHash); err != nil {
			t.Errorf("VerifyFileHash with correct hash returned error: %v", err)
		}
	})

	t.Run("wrong hash", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "testfile.bin")
		if err := os.WriteFile(path, content, 0644); err != nil {
			t.Fatalf("failed to write test file: %v", err)
		}
		wrongHash := strings.Repeat("ab", 32)
		err := VerifyFileHash(path, wrongHash)
		if err == nil {
			t.Error("VerifyFileHash with wrong hash should return error")
		}
		if err != nil && !strings.Contains(err.Error(), "mismatch") {
			t.Errorf("error should mention mismatch, got: %v", err)
		}
	})

	t.Run("non-existent file", func(t *testing.T) {
		err := VerifyFileHash(filepath.Join(t.TempDir(), "no-such-file.bin"), expectedHash)
		if err == nil {
			t.Error("VerifyFileHash with non-existent file should return error")
		}
	})

	t.Run("empty path", func(t *testing.T) {
		err := VerifyFileHash("", expectedHash)
		if err == nil {
			t.Error("VerifyFileHash with empty path should return error")
		}
	})
}

func TestDir(t *testing.T) {
	Init("WhisPasteTest")
	t.Cleanup(func() { Init("") })

	t.Run("returns path under APPDATA", func(t *testing.T) {
		fakeAppData := t.TempDir()
		t.Setenv("APPDATA", fakeAppData)

		dir, err := Dir()
		if err != nil {
			t.Fatalf("Dir() returned error: %v", err)
		}
		if !strings.HasPrefix(dir, fakeAppData) {
			t.Errorf("Dir() = %q, want prefix %q", dir, fakeAppData)
		}
		if !strings.HasSuffix(dir, "models") {
			t.Errorf("Dir() = %q, should end with 'models'", dir)
		}
	})

	t.Run("creates directory on disk", func(t *testing.T) {
		fakeAppData := t.TempDir()
		t.Setenv("APPDATA", fakeAppData)

		dir, err := Dir()
		if err != nil {
			t.Fatalf("Dir() returned error: %v", err)
		}
		info, err := os.Stat(dir)
		if err != nil {
			t.Fatalf("Dir() directory was not created: %v", err)
		}
		if !info.IsDir() {
			t.Error("Dir() path exists but is not a directory")
		}
	})

	t.Run("empty APPDATA returns error", func(t *testing.T) {
		t.Setenv("APPDATA", "")

		_, err := Dir()
		if err == nil {
			t.Error("Dir() with empty APPDATA should return error")
		}
	})
}

func TestGetDir(t *testing.T) {
	Init("WhisPasteTest")
	t.Cleanup(func() { Init("") })

	fakeAppData := t.TempDir()
	t.Setenv("APPDATA", fakeAppData)

	dir, err := GetDir("whisper-small")
	if err != nil {
		t.Fatalf("GetDir() returned error: %v", err)
	}
	if !strings.HasSuffix(dir, "stt") {
		t.Errorf("GetDir() = %q, should end with 'stt'", dir)
	}
}

func TestDownloadFile(t *testing.T) {
	payload := strings.Repeat("A", 1<<20) // 1 MB test payload

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(payload)))
		w.Write([]byte(payload))
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "testfile.bin")

	var reports []int64
	err := DownloadFile(srv.URL+"/model.bin", dest, func(downloaded, total int64) {
		reports = append(reports, downloaded)
	})
	if err != nil {
		t.Fatalf("DownloadFile() error: %v", err)
	}

	data, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read dest: %v", err)
	}
	if len(data) != len(payload) {
		t.Errorf("got %d bytes, want %d", len(data), len(payload))
	}
	if data[0] != 'A' || data[len(data)-1] != 'A' {
		t.Error("content mismatch")
	}

	// Progress should have been reported at least once (final report)
	if len(reports) == 0 {
		t.Error("no progress reports received")
	}
	// With 256 KB debounce interval, a 1 MB file should produce ~4 reports
	if len(reports) > 10 {
		t.Errorf("too many progress reports: got %d, expected ≤10 for 1 MB", len(reports))
	}
}

func TestDownloadFileNoProgressCallback(t *testing.T) {
	payload := "hello"
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(payload))
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "small.bin")
	if err := DownloadFile(srv.URL+"/f", dest, nil); err != nil {
		t.Fatalf("DownloadFile() error: %v", err)
	}

	data, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if string(data) != payload {
		t.Errorf("got %q, want %q", data, payload)
	}
}
