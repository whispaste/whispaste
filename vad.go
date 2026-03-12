package main

import (
	"sync"
)

// VADProcessor provides RMS-based silence detection using the pure-Go
// TrimSilence and StripInternalSilence helpers from audio.go.
type VADProcessor struct {
	mu sync.Mutex
}

var (
	vadInstance *VADProcessor
	vadOnce     sync.Once
)

// GetVADProcessor returns the singleton VADProcessor, initializing it lazily.
func GetVADProcessor() *VADProcessor {
	vadOnce.Do(func() {
		vadInstance = &VADProcessor{}
	})
	return vadInstance
}

// ProcessPCM takes raw 16kHz mono int16 PCM, removes silence based on
// RMS energy, and returns the trimmed audio. sensitivity (0.0–1.0) controls
// how aggressively silence is detected: 0 = strict, 1 = very sensitive.
func (v *VADProcessor) ProcessPCM(pcm []byte, sensitivity float32) ([]byte, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if len(pcm) < 2 {
		return pcm, nil
	}

	// Map sensitivity to RMS threshold.
	// sensitivity 0.0 → 0.05 (strict, only loud silence removed)
	// sensitivity 1.0 → 0.005 (sensitive, catches quiet gaps)
	threshold := float32(0.05) - sensitivity*0.045
	if threshold < 0.005 {
		threshold = 0.005
	}
	if threshold > 0.05 {
		threshold = 0.05
	}

	result := TrimSilence(pcm, threshold, 30)
	result = StripInternalSilence(result, threshold, 500)

	logDebug("VAD processed: %d → %d bytes (%.1f%% kept)",
		len(pcm), len(result), float64(len(result))/float64(len(pcm))*100)
	return result, nil
}

// Close releases VAD resources (no-op for RMS-based detection).
func (v *VADProcessor) Close() {
	v.mu.Lock()
	defer v.mu.Unlock()
	logInfo("VAD processor closed")
}
