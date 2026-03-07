package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

const (
	vadModelURL  = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
	vadModelFile = "silero_vad.onnx"
	vadModelSize = int64(2_000_000) // approximate size for progress reporting
)

// VADProcessor wraps a sherpa-onnx Silero VAD for extracting speech segments.
type VADProcessor struct {
	mu sync.Mutex
}

var (
	vadInstance *VADProcessor
	vadOnce    sync.Once
)

// GetVADProcessor returns the singleton VADProcessor, initializing it lazily.
func GetVADProcessor() *VADProcessor {
	vadOnce.Do(func() {
		vadInstance = &VADProcessor{}
	})
	return vadInstance
}

// vadModelDir returns the directory where the VAD model is stored.
func vadModelDir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, AppName, "models", "vad")
	return dir, os.MkdirAll(dir, 0700)
}

// ensureModel downloads the Silero VAD model if not already present.
func (v *VADProcessor) ensureModel() (string, error) {
	dir, err := vadModelDir()
	if err != nil {
		return "", fmt.Errorf("vad model dir: %w", err)
	}
	dest := filepath.Join(dir, vadModelFile)

	if info, err := os.Stat(dest); err == nil && info.Size() > 0 {
		return dest, nil
	}

	logInfo("Downloading Silero VAD model...")
	var lastPct int = -1
	if err := downloadModelFile(vadModelURL, dest, func(downloaded, total int64) {
		if total <= 0 {
			total = vadModelSize
		}
		pct := int(float64(downloaded) / float64(total) * 100)
		if pct > 100 {
			pct = 100
		}
		if pct != lastPct && pct%25 == 0 {
			lastPct = pct
			logDebug("VAD model download: %d%%", pct)
		}
	}); err != nil {
		return "", fmt.Errorf("download vad model: %w", err)
	}
	logInfo("Silero VAD model downloaded: %s", dest)
	return dest, nil
}

// ProcessPCM takes raw 16kHz mono int16 PCM and returns only voiced segments
// concatenated together. silence is removed based on the Silero VAD model.
func (v *VADProcessor) ProcessPCM(pcm []byte, sensitivity float32) ([]byte, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if len(pcm) < 2 {
		return pcm, nil
	}

	modelPath, err := v.ensureModel()
	if err != nil {
		return nil, fmt.Errorf("vad model not available: %w", err)
	}

	// Map sensitivity (0.0–1.0) to VAD threshold.
	// Higher sensitivity → lower threshold → more speech detected.
	// Default sensitivity 0.5 → threshold 0.5
	// Sensitivity 1.0 → threshold 0.1 (very sensitive, catches quiet speech)
	// Sensitivity 0.0 → threshold 0.9 (strict, only loud speech)
	threshold := 0.9 - sensitivity*0.8
	if threshold < 0.1 {
		threshold = 0.1
	}
	if threshold > 0.9 {
		threshold = 0.9
	}

	config := &sherpa.VadModelConfig{
		SileroVad: sherpa.SileroVadModelConfig{
			Model:              modelPath,
			Threshold:          float32(threshold),
			MinSilenceDuration: 0.25,
			MinSpeechDuration:  0.25,
			WindowSize:         512,
		},
		SampleRate: 16000,
		NumThreads: 1,
		Provider:   "cpu",
		Debug:      0,
	}

	vad := sherpa.NewVoiceActivityDetector(config, 30.0)
	if vad == nil {
		return nil, fmt.Errorf("failed to create VAD detector")
	}
	defer sherpa.DeleteVoiceActivityDetector(vad)

	// Convert PCM int16 to float32 samples
	samples := pcmToFloat32(pcm)

	const windowSize = 512
	for i := 0; i+windowSize <= len(samples); i += windowSize {
		vad.AcceptWaveform(samples[i : i+windowSize])
	}
	// Feed remaining samples that don't fill a complete window
	if remainder := len(samples) % windowSize; remainder > 0 {
		vad.AcceptWaveform(samples[len(samples)-remainder:])
	}
	vad.Flush()

	// Collect voiced segments
	var voicedSamples []float32
	for !vad.IsEmpty() {
		segment := vad.Front()
		if segment != nil && len(segment.Samples) > 0 {
			voicedSamples = append(voicedSamples, segment.Samples...)
		}
		vad.Pop()
	}

	if len(voicedSamples) == 0 {
		logDebug("VAD: no speech segments detected, returning original audio")
		return pcm, nil
	}

	// Convert float32 samples back to int16 PCM
	result := float32ToPCM(voicedSamples)
	logDebug("VAD processed: %d → %d bytes (%.1f%% speech)",
		len(pcm), len(result), float64(len(result))/float64(len(pcm))*100)
	return result, nil
}

// float32ToPCM converts float32 samples in [-1, 1] to PCM int16 little-endian bytes.
func float32ToPCM(samples []float32) []byte {
	out := make([]byte, len(samples)*2)
	for i, s := range samples {
		if s > 1.0 {
			s = 1.0
		} else if s < -1.0 {
			s = -1.0
		}
		val := int16(s * 32767)
		out[i*2] = byte(val)
		out[i*2+1] = byte(val >> 8)
	}
	return out
}

// Close releases VAD resources.
func (v *VADProcessor) Close() {
	v.mu.Lock()
	defer v.mu.Unlock()
	logInfo("VAD processor closed")
}
