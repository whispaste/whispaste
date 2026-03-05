package main

import (
	"fmt"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	sherpa "github.com/k2-fsa/sherpa-onnx-go/sherpa_onnx"
)

// numThreads returns a safe thread count for sherpa-onnx.
// Official docs recommend 2; we cap at 4 as a balance between speed and stability.
func numThreads() int {
	n := runtime.NumCPU()
	if n > 4 {
		return 4
	}
	return n
}

// normalizeLanguage maps the config value to what sherpa-onnx expects.
// sherpa-onnx uses ISO codes ("en","de") or "" for auto-detection.
// Our config uses "auto" for auto-detection, which must be mapped to "".
func normalizeLanguage(lang string) string {
	if lang == "auto" || lang == "" {
		return ""
	}
	return lang
}

// pcmToFloat32 converts PCM int16 little-endian bytes to float32 samples in [-1, 1].
func pcmToFloat32(pcm []byte) []float32 {
	numSamples := len(pcm) / 2
	samples := make([]float32, numSamples)
	for i := 0; i < numSamples; i++ {
		val := int16(pcm[i*2]) | int16(pcm[i*2+1])<<8
		samples[i] = float32(val) / 32768.0
	}
	return samples
}

// TranscribeLocal performs offline speech-to-text using a local sherpa-onnx Whisper model.
func TranscribeLocal(pcmS16 []byte, sampleRate int, language string, modelDir string) (string, error) {
	if len(pcmS16) < 2 {
		return "", fmt.Errorf("audio data too short")
	}

	// Resolve model file paths by scanning Files list for encoder/decoder/tokens.
	model := findModelByDir(modelDir)
	if model == nil {
		return "", fmt.Errorf("unknown model directory: %s", modelDir)
	}

	encoder, decoder, tokens := resolveModelFiles(model, modelDir)
	if encoder == "" || decoder == "" || tokens == "" {
		return "", fmt.Errorf("incomplete model files in %s", modelDir)
	}

	config := &sherpa.OfflineRecognizerConfig{
		FeatConfig: sherpa.FeatureConfig{
			SampleRate: sampleRate,
			FeatureDim: 80,
		},
		ModelConfig: sherpa.OfflineModelConfig{
			Whisper: sherpa.OfflineWhisperModelConfig{
				Encoder:  encoder,
				Decoder:  decoder,
				Language: normalizeLanguage(language),
				Task:     "transcribe",
			},
			Tokens:     tokens,
			NumThreads: numThreads(),
			Provider:   "cpu",
			Debug:      0,
		},
		DecodingMethod: "greedy_search",
	}

	recognizer := sherpa.NewOfflineRecognizer(config)
	if recognizer == nil {
		return "", fmt.Errorf("failed to create offline recognizer")
	}
	defer sherpa.DeleteOfflineRecognizer(recognizer)

	stream := sherpa.NewOfflineStream(recognizer)
	if stream == nil {
		return "", fmt.Errorf("failed to create offline stream")
	}
	defer sherpa.DeleteOfflineStream(stream)

	samples := pcmToFloat32(pcmS16)
	stream.AcceptWaveform(sampleRate, samples)
	recognizer.Decode(stream)

	result := stream.GetResult()
	return strings.TrimSpace(result.Text), nil
}

// findModelByDir returns the ModelInfo whose ID matches the last path component of dir.
func findModelByDir(dir string) *ModelInfo {
	base := filepath.Base(dir)
	for i := range AvailableModels {
		if AvailableModels[i].ID == base {
			return &AvailableModels[i]
		}
	}
	return nil
}

// resolveModelFiles returns full paths for encoder, decoder, and tokens files.
func resolveModelFiles(m *ModelInfo, dir string) (encoder, decoder, tokens string) {
	for _, f := range m.Files {
		path := filepath.Join(dir, f)
		switch {
		case strings.Contains(f, "encoder"):
			encoder = path
		case strings.Contains(f, "decoder"):
			decoder = path
		case strings.Contains(f, "tokens"):
			tokens = path
		}
	}
	return
}

// LocalRecognizer is a thread-safe singleton that caches a sherpa-onnx recognizer
// to avoid reloading the model on every transcription.
type LocalRecognizer struct {
	mu         sync.Mutex
	recognizer *sherpa.OfflineRecognizer
	modelDir   string
	language   string
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

// Transcribe performs speech-to-text, reusing the cached recognizer when possible.
// The recognizer is re-created if modelDir or language has changed.
// For audio longer than 30 seconds, it processes in overlapping chunks.
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

	if len(pcmS16) < 2 {
		return "", fmt.Errorf("audio data too short")
	}

	// Re-create recognizer if settings changed or not yet initialized.
	if lr.recognizer == nil || lr.modelDir != modelDir || lr.language != language {
		if lr.recognizer != nil {
			sherpa.DeleteOfflineRecognizer(lr.recognizer)
			lr.recognizer = nil
		}

		model := findModelByDir(modelDir)
		if model == nil {
			return "", fmt.Errorf("unknown model directory: %s", modelDir)
		}

		encoder, decoder, tokens := resolveModelFiles(model, modelDir)
		if encoder == "" || decoder == "" || tokens == "" {
			return "", fmt.Errorf("incomplete model files in %s", modelDir)
		}

		config := &sherpa.OfflineRecognizerConfig{
			FeatConfig: sherpa.FeatureConfig{
				SampleRate: sampleRate,
				FeatureDim: 80,
			},
			ModelConfig: sherpa.OfflineModelConfig{
				Whisper: sherpa.OfflineWhisperModelConfig{
					Encoder:  encoder,
					Decoder:  decoder,
					Language: normalizeLanguage(language),
					Task:     "transcribe",
				},
				Tokens:     tokens,
				NumThreads: numThreads(),
				Provider:   "cpu",
				Debug:      0,
			},
			DecodingMethod: "greedy_search",
		}

		rec := sherpa.NewOfflineRecognizer(config)
		if rec == nil {
			return "", fmt.Errorf("failed to create offline recognizer")
		}
		lr.recognizer = rec
		lr.modelDir = modelDir
		lr.language = language
		logInfo("local recognizer initialized: model=%s lang=%s", modelDir, language)
		logDebug("recognizer config: threads=%d lang=%q model=%s", numThreads(), normalizeLanguage(language), modelDir)
	}

	samples := pcmToFloat32(pcmS16)
	modelName := filepath.Base(modelDir)
	nThreads := numThreads()
	logInfo("Local transcription: model=%s audioSamples=%d threads=%d", modelName, len(samples), nThreads)
	transcribeStart := time.Now()

	// Whisper has a ~30s context window. Process in chunks for longer audio.
	const chunkSec = 28
	chunkSamples := chunkSec * sampleRate

	chunkMode := "single"
	if len(samples) > 30*sampleRate {
		chunkMode = "chunked"
	}
	logDebug("transcribing: totalSamples=%d duration=%.1fs chunks=%s", len(samples), float64(len(samples))/float64(sampleRate), chunkMode)

	if len(samples) <= 30*sampleRate {
		// Short audio (≤30s): process in one shot
		text, chunkErr := lr.transcribeChunk(samples, sampleRate)
		if chunkErr != nil {
			return text, chunkErr
		}
		logInfo("Local transcription complete: model=%s duration=%v textLen=%d", modelName, time.Since(transcribeStart), len(text))
		return text, nil
	}

	// Long audio: process in sequential chunks and concatenate
	var parts []string
	totalChunks := 0
	failedChunks := 0
	offset := 0
	for offset < len(samples) {
		end := offset + chunkSamples
		if end > len(samples) {
			end = len(samples)
		}
		chunk := samples[offset:end]
		totalChunks++

		text, err := lr.transcribeChunk(chunk, sampleRate)
		if err != nil {
			failedChunks++
			logWarn("chunk transcription error at offset %d: %v", offset, err)
		} else if text != "" {
			parts = append(parts, text)
		}

		if end >= len(samples) {
			break
		}
		offset = end
	}
	if totalChunks > 0 && failedChunks*2 > totalChunks {
		return "", fmt.Errorf("transcription failed: %d of %d chunks failed", failedChunks, totalChunks)
	}
	joined := strings.Join(parts, " ")
	logInfo("Local transcription complete: model=%s duration=%v textLen=%d", modelName, time.Since(transcribeStart), len(joined))
	return joined, nil
}

// transcribeChunk transcribes a single chunk of float32 samples.
func (lr *LocalRecognizer) transcribeChunk(samples []float32, sampleRate int) (string, error) {
	logDebug("transcribeChunk: creating stream, samples=%d duration=%.1fs", len(samples), float64(len(samples))/float64(sampleRate))
	stream := sherpa.NewOfflineStream(lr.recognizer)
	if stream == nil {
		return "", fmt.Errorf("failed to create offline stream")
	}
	defer sherpa.DeleteOfflineStream(stream)

	logDebug("transcribeChunk: accepting waveform")
	stream.AcceptWaveform(sampleRate, samples)
	logDebug("transcribeChunk: starting decode")
	lr.recognizer.Decode(stream)
	logDebug("transcribeChunk: decode complete, getting result")

	result := stream.GetResult()
	text := strings.TrimSpace(result.Text)
	logDebug("transcribeChunk: result len=%d", len(text))
	return text, nil
}

// Close releases the cached recognizer resources.
func (lr *LocalRecognizer) Close() {
	lr.mu.Lock()
	defer lr.mu.Unlock()

	if lr.recognizer != nil {
		sherpa.DeleteOfflineRecognizer(lr.recognizer)
		lr.recognizer = nil
		logInfo("local recognizer closed")
	}
	lr.modelDir = ""
	lr.language = ""
}
