package main

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// validAudioID matches hex-only IDs (8-32 chars) to prevent path traversal.
var validAudioID = regexp.MustCompile(`^[0-9a-f]{8,32}$`)

// AudioCacheDir returns the audio cache directory, creating it if needed.
func AudioCacheDir() (string, error) {
	dir, err := configDir()
	if err != nil {
		return "", fmt.Errorf("config dir: %w", err)
	}
	audioDir := filepath.Join(dir, "audio")
	if err := os.MkdirAll(audioDir, 0700); err != nil {
		return "", fmt.Errorf("create audio dir: %w", err)
	}
	return audioDir, nil
}

// SaveAudio saves WAV-encoded audio for a history entry.
// The pcm data is encoded to WAV (16kHz/16bit/mono) before saving.
func SaveAudio(id string, pcm []byte) error {
	if !validAudioID.MatchString(id) {
		return fmt.Errorf("invalid audio ID: %q", id)
	}
	if len(pcm) == 0 {
		return nil
	}
	dir, err := AudioCacheDir()
	if err != nil {
		return err
	}
	wav := EncodeWAV(pcm, 16000, 1, 16)

	// Gzip compress
	var buf bytes.Buffer
	gz, err := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if err != nil {
		return fmt.Errorf("create gzip writer: %w", err)
	}
	if _, err := gz.Write(wav); err != nil {
		gz.Close()
		return fmt.Errorf("gzip write: %w", err)
	}
	if err := gz.Close(); err != nil {
		return fmt.Errorf("gzip close: %w", err)
	}
	compressed := buf.Bytes()

	path := filepath.Join(dir, id+".wav")
	if err := os.WriteFile(path, compressed, 0600); err != nil {
		return fmt.Errorf("write audio file: %w", err)
	}
	logDebug("Saved audio cache: %s (%d bytes WAV → %d bytes gzip, %.0f%% saved)", id, len(wav), len(compressed), (1-float64(len(compressed))/float64(len(wav)))*100)
	return nil
}

// LoadAudio loads the cached WAV file for a history entry.
// Returns the raw WAV bytes (with header) or an error.
func LoadAudio(id string) ([]byte, error) {
	if !validAudioID.MatchString(id) {
		return nil, fmt.Errorf("invalid audio ID: %q", id)
	}
	dir, err := AudioCacheDir()
	if err != nil {
		return nil, err
	}
	path := filepath.Join(dir, id+".wav")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read audio file: %w", err)
	}
	// Transparently decompress gzip (new format) or return raw WAV (old format)
	if len(data) >= 2 && data[0] == 0x1f && data[1] == 0x8b {
		gr, err := gzip.NewReader(bytes.NewReader(data))
		if err != nil {
			return nil, fmt.Errorf("gzip reader: %w", err)
		}
		defer gr.Close()
		decompressed, err := io.ReadAll(gr)
		if err != nil {
			return nil, fmt.Errorf("gzip decompress: %w", err)
		}
		return decompressed, nil
	}
	return data, nil
}

// HasAudio checks whether a cached audio file exists for the given entry ID.
func HasAudio(id string) bool {
	if !validAudioID.MatchString(id) {
		return false
	}
	dir, err := AudioCacheDir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, id+".wav"))
	return err == nil
}

// DeleteAudio removes the cached audio file for an entry (if it exists).
func DeleteAudio(id string) {
	if !validAudioID.MatchString(id) {
		return
	}
	dir, err := AudioCacheDir()
	if err != nil {
		return
	}
	path := filepath.Join(dir, id+".wav")
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		logWarn("Delete audio file %s: %v", id, err)
	}
}

// CleanupOrphanedAudio removes audio files that don't belong to any valid entry.
func CleanupOrphanedAudio(validIDs map[string]bool) {
	dir, err := AudioCacheDir()
	if err != nil {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		logWarn("Read audio dir: %v", err)
		return
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".wav") {
			continue
		}
		id := strings.TrimSuffix(name, ".wav")
		if !validIDs[id] {
			path := filepath.Join(dir, name)
			if err := os.Remove(path); err != nil {
				logWarn("Cleanup orphaned audio %s: %v", name, err)
			} else {
				logDebug("Removed orphaned audio: %s", name)
			}
		}
	}
}
