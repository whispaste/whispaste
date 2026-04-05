// Package inference provides centralized configuration for local and cloud
// inference parameters, replacing hardcoded values throughout the codebase.
package inference

import "runtime"

// Profile holds tuning parameters for a specific use case.
type Profile struct {
	Temperature float64
	MaxTokens   int
	TopP        float64
	CtxSize     int // context window size for local LLM (0 = use default)
}

// Predefined profiles for different use cases.
var (
	Precise = Profile{
		Temperature: 0.1,
		MaxTokens:   1024,
		TopP:        0.9,
		CtxSize:     2048,
	}
	Balanced = Profile{
		Temperature: 0.3,
		MaxTokens:   2048,
		TopP:        0.95,
		CtxSize:     2048,
	}
	Creative = Profile{
		Temperature: 0.7,
		MaxTokens:   2048,
		TopP:        0.95,
		CtxSize:     2048,
	}
	Factual = Profile{
		Temperature: 0.0,
		MaxTokens:   2048,
		TopP:        1.0,
		CtxSize:     2048,
	}
)

// ProfileForPreset maps a text-refinement preset name to an inference profile.
func ProfileForPreset(preset string) Profile {
	switch preset {
	case "cleanup", "concise":
		return Precise
	case "email":
		return Precise
	case "bullets", "formal", "aiprompt", "summary", "meeting":
		return Balanced
	case "social", "casual":
		return Creative
	case "notes":
		return Factual
	default:
		return Balanced
	}
}

// AutoTagProfile returns the profile used for automatic tagging.
func AutoTagProfile() Profile {
	return Profile{
		Temperature: 0.1,
		MaxTokens:   100,
		TopP:        0.9,
	}
}

// STTTemperature returns the temperature for local STT inference.
func STTTemperature() float64 {
	return 0.0
}

// OptimalThreads calculates the optimal thread count for local inference.
// It uses 75% of available CPUs, clamped between min and max.
func OptimalThreads(minThreads, maxThreads int) int {
	n := runtime.NumCPU() * 3 / 4
	if n < minThreads {
		n = minThreads
	}
	if n > maxThreads {
		n = maxThreads
	}
	return n
}

// STTThreads returns the optimal thread count for whisper.cpp (general).
func STTThreads() int {
	return OptimalThreads(2, 12)
}

// STTThreadsGPU returns the thread count for GPU-accelerated whisper.cpp.
// GPU handles the heavy encoder work; CPU threads only assist with token
// decoding and pre/post-processing — fewer threads avoids contention.
func STTThreadsGPU() int {
	return OptimalThreads(2, 8)
}

// STTThreadsCPUOnly keeps one extra core free on CPU-only systems for UI/audio responsiveness.
func STTThreadsCPUOnly() int {
	n := runtime.NumCPU() - 1
	if n < 2 {
		n = 2
	}
	if n > 12 {
		n = 12
	}
	return n
}

// LLMThreads returns the optimal thread count for llama.cpp.
func LLMThreads() int {
	return OptimalThreads(2, 12)
}

// LLMCtxSize returns the context size for local LLM, using the profile's
// value if set, otherwise the default.
func LLMCtxSize(profile Profile) int {
	if profile.CtxSize > 0 {
		return profile.CtxSize
	}
	return 2048
}
