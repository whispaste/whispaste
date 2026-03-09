package audiocache

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/whispaste/whispaste/internal/wav"
)

// ValidID matches hex-only IDs (8-32 chars) to prevent path traversal.
var ValidID = regexp.MustCompile(`^[0-9a-f]{8,32}$`)

var baseDir string

// Init sets the base directory for the audio cache (e.g. configDir).
func Init(dir string) {
	baseDir = dir
}

// Dir returns the audio cache directory, creating it if needed.
func Dir() (string, error) {
	if baseDir == "" {
		return "", fmt.Errorf("audiocache: not initialized (call Init first)")
	}
	audioDir := filepath.Join(baseDir, "audio")
	if err := os.MkdirAll(audioDir, 0700); err != nil {
		return "", fmt.Errorf("create audio dir: %w", err)
	}
	return audioDir, nil
}

// Save saves WAV-encoded audio for a history entry.
// The pcm data is encoded to WAV (16kHz/16bit/mono) before saving.
func Save(id string, pcm []byte) error {
	if !ValidID.MatchString(id) {
		return fmt.Errorf("invalid audio ID: %q", id)
	}
	if len(pcm) == 0 {
		return nil
	}
	dir, err := Dir()
	if err != nil {
		return err
	}
	wavData := wav.Encode(pcm, 16000, 1, 16)

	// Gzip compress
	var buf bytes.Buffer
	gz, err := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if err != nil {
		return fmt.Errorf("create gzip writer: %w", err)
	}
	if _, err := gz.Write(wavData); err != nil {
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
	return nil
}

// Load loads the cached WAV file for a history entry.
// Returns the raw WAV bytes (with header) or an error.
func Load(id string) ([]byte, error) {
	if !ValidID.MatchString(id) {
		return nil, fmt.Errorf("invalid audio ID: %q", id)
	}
	dir, err := Dir()
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

// Has checks whether a cached audio file exists for the given entry ID.
func Has(id string) bool {
	if !ValidID.MatchString(id) {
		return false
	}
	dir, err := Dir()
	if err != nil {
		return false
	}
	_, err = os.Stat(filepath.Join(dir, id+".wav"))
	return err == nil
}

// Delete removes the cached audio file for an entry (if it exists),
// including any indexed files from merges ({id}_1.wav, {id}_2.wav, …).
func Delete(id string) error {
	if !ValidID.MatchString(id) {
		return fmt.Errorf("invalid audio ID: %q", id)
	}
	dir, err := Dir()
	if err != nil {
		return err
	}
	// Delete primary file
	p := filepath.Join(dir, id+".wav")
	if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("delete audio file %s: %w", id, err)
	}
	// Delete any indexed files from merge
	for i := 1; ; i++ {
		ip := filepath.Join(dir, fmt.Sprintf("%s_%d.wav", id, i))
		if err := os.Remove(ip); err != nil {
			break
		}
	}
	return nil
}

// CopyForMerge copies audio files from source entry IDs to a merged target ID.
// Returns the number of audio files successfully copied.
// Handles sources that are themselves merged (with indexed files).
func CopyForMerge(sourceIDs []string, targetID string) int {
	dir, err := Dir()
	if err != nil {
		return 0
	}
	copied := 0
	for _, srcID := range sourceIDs {
		srcCount := AudioCount(srcID)
		if srcCount == 0 {
			continue
		}
		for j := 0; j < srcCount; j++ {
			var srcPath string
			if j == 0 {
				srcPath = filepath.Join(dir, srcID+".wav")
			} else {
				srcPath = filepath.Join(dir, fmt.Sprintf("%s_%d.wav", srcID, j))
			}
			var dstPath string
			if copied == 0 {
				dstPath = filepath.Join(dir, targetID+".wav")
			} else {
				dstPath = filepath.Join(dir, fmt.Sprintf("%s_%d.wav", targetID, copied))
			}
			data, err := os.ReadFile(srcPath)
			if err != nil {
				continue
			}
			if err := os.WriteFile(dstPath, data, 0600); err != nil {
				continue
			}
			copied++
		}
	}
	return copied
}

// AudioCount returns how many audio files exist for the given entry ID.
// Returns 0 if no audio, 1 for a single file, 2+ for merged entries.
func AudioCount(id string) int {
	if !Has(id) {
		return 0
	}
	dir, err := Dir()
	if err != nil {
		return 0
	}
	count := 1
	for i := 1; ; i++ {
		p := filepath.Join(dir, fmt.Sprintf("%s_%d.wav", id, i))
		if _, err := os.Stat(p); err != nil {
			break
		}
		count++
	}
	return count
}

// LoadByIndex loads a specific audio file for merged entries.
// Index 0 loads {id}.wav, index N loads {id}_N.wav.
func LoadByIndex(id string, idx int) ([]byte, error) {
	if !ValidID.MatchString(id) {
		return nil, fmt.Errorf("invalid audio ID: %q", id)
	}
	if idx < 0 {
		return nil, fmt.Errorf("invalid audio index: %d", idx)
	}
	dir, err := Dir()
	if err != nil {
		return nil, err
	}
	var path string
	if idx == 0 {
		path = filepath.Join(dir, id+".wav")
	} else {
		path = filepath.Join(dir, fmt.Sprintf("%s_%d.wav", id, idx))
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read audio file: %w", err)
	}
	// Transparently decompress gzip or return raw WAV
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

// CleanupOrphaned removes audio files that don't belong to any valid entry.
// Returns the number of files removed.
func CleanupOrphaned(validIDs map[string]bool) int {
	dir, err := Dir()
	if err != nil {
		return 0
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	removed := 0
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".wav") {
			continue
		}
		id := strings.TrimSuffix(name, ".wav")
		// Handle indexed audio files from merges (e.g., "abc123_2.wav" → base ID "abc123")
		baseID := id
		if idx := strings.LastIndex(id, "_"); idx > 0 {
			suffix := id[idx+1:]
			allDigits := len(suffix) > 0
			for _, c := range suffix {
				if c < '0' || c > '9' {
					allDigits = false
					break
				}
			}
			if allDigits {
				baseID = id[:idx]
			}
		}
		if !validIDs[baseID] {
			path := filepath.Join(dir, name)
			if err := os.Remove(path); err == nil {
				removed++
			}
		}
	}
	return removed
}
