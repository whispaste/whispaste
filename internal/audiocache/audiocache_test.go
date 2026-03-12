package audiocache

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestValidID(t *testing.T) {
	tests := []struct {
		id    string
		valid bool
	}{
		{"0123456789abcdef", true},                    // 16 hex chars
		{"abcdef01", true},                            // 8 hex chars (minimum)
		{"0123456789abcdef01234567", true},            // 24 hex chars
		{"ABCDEF01", false},                           // uppercase
		{"../etc/passwd", false},                      // path traversal
		{"abc", false},                                // too short
		{"ghijklmn", false},                           // non-hex
		{"", false},                                   // empty
		{"abcdefgh01234567890123456789012345", false}, // >32 chars
	}
	for _, tt := range tests {
		t.Run(tt.id, func(t *testing.T) {
			got := ValidID.MatchString(tt.id)
			if got != tt.valid {
				t.Errorf("ValidID(%q) = %v, want %v", tt.id, got, tt.valid)
			}
		})
	}
}

func TestSaveLoadRoundtrip(t *testing.T) {
	tmpDir := t.TempDir()
	Init(tmpDir)

	// Create PCM test data (16-bit LE samples)
	pcm := make([]byte, 3200) // 100ms at 16kHz
	for i := 0; i < len(pcm); i += 2 {
		pcm[i] = byte(i % 256)
		pcm[i+1] = byte((i / 2) % 128)
	}

	id := "aabbccdd11223344"
	if err := Save(id, pcm); err != nil {
		t.Fatalf("Save: %v", err)
	}

	if !Has(id) {
		t.Error("Has returned false after save")
	}

	loaded, err := Load(id)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	// Loaded data should be WAV (starts with RIFF header)
	if len(loaded) < 44 {
		t.Fatalf("loaded WAV too short: %d bytes", len(loaded))
	}
	if string(loaded[:4]) != "RIFF" {
		t.Error("loaded data does not start with RIFF header")
	}

	// WAV data section should contain our original PCM
	wavData := loaded[44:]
	if !bytes.Equal(wavData, pcm) {
		t.Error("WAV data section does not match original PCM")
	}
}

func TestSaveInvalidID(t *testing.T) {
	tmpDir := t.TempDir()
	Init(tmpDir)

	err := Save("../../../etc/evil", []byte{1, 2})
	if err == nil {
		t.Error("expected error for path-traversal ID")
	}
}

func TestSaveEmptyPCM(t *testing.T) {
	tmpDir := t.TempDir()
	Init(tmpDir)

	err := Save("aabbccdd11223344", nil)
	if err != nil {
		t.Errorf("empty PCM should succeed (no-op), got: %v", err)
	}
}

func TestCleanupOrphaned(t *testing.T) {
	tmpDir := t.TempDir()
	Init(tmpDir)

	audioDir := filepath.Join(tmpDir, "audio")
	os.MkdirAll(audioDir, 0700)

	// Create some fake audio files
	os.WriteFile(filepath.Join(audioDir, "aabbccdd00000001.wav"), []byte("data"), 0600)
	os.WriteFile(filepath.Join(audioDir, "aabbccdd00000002.wav"), []byte("data"), 0600)
	os.WriteFile(filepath.Join(audioDir, "aabbccdd00000003.wav"), []byte("data"), 0600)

	// Only ID 1 and 3 are valid
	validIDs := map[string]bool{
		"aabbccdd00000001": true,
		"aabbccdd00000003": true,
	}
	CleanupOrphaned(validIDs)

	// ID 2 should be removed
	if _, err := os.Stat(filepath.Join(audioDir, "aabbccdd00000002.wav")); !os.IsNotExist(err) {
		t.Error("orphaned audio file should have been removed")
	}
	// ID 1 and 3 should remain
	if _, err := os.Stat(filepath.Join(audioDir, "aabbccdd00000001.wav")); err != nil {
		t.Error("valid audio file 1 should not have been removed")
	}
	if _, err := os.Stat(filepath.Join(audioDir, "aabbccdd00000003.wav")); err != nil {
		t.Error("valid audio file 3 should not have been removed")
	}
}
