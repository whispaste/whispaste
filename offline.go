package main

import (
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/whispaste/whispaste/internal/wav"
)

// normalizeLanguage maps the config value to what whisper.cpp expects.
// whisper.cpp uses ISO codes ("en","de") or "" for auto-detection.
// Our config uses "auto" for auto-detection, which must be mapped to "".
func normalizeLanguage(lang string) string {
	if lang == "auto" || lang == "" {
		return ""
	}
	return lang
}

// TranscribeLocal performs offline speech-to-text via the local whisper.cpp HTTP server.
func TranscribeLocal(pcmS16 []byte, sampleRate int, language string, modelID string) (string, error) {
	if len(pcmS16) < 2 {
		return "", fmt.Errorf("audio data too short")
	}

	modelPath, err := STTModelPath(modelID)
	if err != nil {
		return "", fmt.Errorf("resolve model path: %w", err)
	}

	if _, err := localSTT.Start(modelPath); err != nil {
		return "", fmt.Errorf("start STT server: %w", err)
	}

	wavData := wav.Encode(pcmS16, uint32(sampleRate), 1, 16)
	lang := normalizeLanguage(language)

	text, err := localSTT.Transcribe(wavData, lang)
	if err != nil {
		return "", fmt.Errorf("transcribe: %w", err)
	}

	return strings.TrimSpace(text), nil
}

// LocalRecognizer is a thread-safe singleton wrapper around the whisper.cpp HTTP server.
type LocalRecognizer struct {
	mu sync.Mutex
}

var localRec *LocalRecognizer
var localRecOnce sync.Once

// GetLocalRecognizer returns the singleton LocalRecognizer instance.
func GetLocalRecognizer() *LocalRecognizer {
	localRecOnce.Do(func() {
		localRec = &LocalRecognizer{}
	})
	return localRec
}

// Transcribe performs speech-to-text via the local whisper.cpp server.
// modelDir is kept for backward compatibility — the modelID is extracted via filepath.Base.
func (lr *LocalRecognizer) Transcribe(pcmS16 []byte, sampleRate int, language, modelDir string) (result string, err error) {
	defer func() {
		if r := recover(); r != nil {
			logError("Local transcription PANIC: %v", r)
			result = ""
			err = fmt.Errorf("local transcription panic: %v", r)
		}
	}()

	lr.mu.Lock()
	defer lr.mu.Unlock()

	modelID := filepath.Base(modelDir)
	logInfo("Local transcription: model=%s pcmBytes=%d sampleRate=%d", modelID, len(pcmS16), sampleRate)
	start := time.Now()

	text, err := TranscribeLocal(pcmS16, sampleRate, language, modelID)
	if err != nil {
		return "", err
	}

	logInfo("Local transcription complete: model=%s duration=%v textLen=%d", modelID, time.Since(start), len(text))
	return text, nil
}

// Close stops the whisper.cpp STT server.
func (lr *LocalRecognizer) Close() {
	lr.mu.Lock()
	defer lr.mu.Unlock()

	localSTT.Stop()
	logInfo("local recognizer closed")
}
