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

func startLocalSTTModel(s *LocalSTT, modelID string) error {
	modelPath, err := STTModelPath(modelID)
	if err != nil {
		return fmt.Errorf("resolve model path: %w", err)
	}
	if _, err := s.Start(modelPath); err != nil {
		return fmt.Errorf("start STT server: %w", err)
	}
	return nil
}

func transcribeLocalWithSTT(s *LocalSTT, pcmS16 []byte, sampleRate int, language string, modelID string, prompt ...string) (string, error) {
	if len(pcmS16) < 2 {
		return "", fmt.Errorf("audio data too short")
	}

	serverStart := time.Now()
	if err := startLocalSTTModel(s, modelID); err != nil {
		return "", err
	}
	serverDur := time.Since(serverStart)

	wavData := wav.Encode(pcmS16, uint32(sampleRate), 1, 16)
	lang := normalizeLanguage(language)

	var promptArg []string
	if len(prompt) > 0 && prompt[0] != "" {
		promptArg = prompt
	}
	inferStart := time.Now()
	text, err := s.Transcribe(wavData, lang, promptArg...)
	inferDur := time.Since(inferStart)
	audioDur := float64(len(pcmS16)) / float64(sampleRate*2) // 16-bit mono
	logInfo("Local STT timing: serverStart=%v inference=%v audioDur=%.1fs model=%s textLen=%d", serverDur, inferDur, audioDur, modelID, len(text))
	if err != nil {
		return "", fmt.Errorf("transcribe: %w", err)
	}

	return strings.TrimSpace(text), nil
}

// TranscribeLocal performs offline speech-to-text via the local whisper.cpp HTTP server.
// An optional prompt parameter can be passed (e.g. custom dictionary terms) to improve recognition.
func TranscribeLocal(pcmS16 []byte, sampleRate int, language string, modelID string, prompt ...string) (string, error) {
	return transcribeLocalWithSTT(&localSTT, pcmS16, sampleRate, language, modelID, prompt...)
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
