// Package provider defines interfaces and implementations for STT and LLM providers.
// It supports multiple cloud providers (OpenAI, Groq, Deepgram, Anthropic, Gemini)
// as well as local inference via whisper.cpp and llama.cpp.
package provider

import "context"

// STTProvider transcribes audio to text.
type STTProvider interface {
	// Name returns the provider identifier (e.g. "openai", "groq", "local").
	Name() string
	// Transcribe converts audio data (WAV format) to text.
	Transcribe(ctx context.Context, audio []byte, lang string, opts STTOptions) (string, error)
}

// LLMProvider processes text via chat completion.
type LLMProvider interface {
	// Name returns the provider identifier.
	Name() string
	// ChatCompletion sends messages and returns the assistant's response.
	ChatCompletion(ctx context.Context, messages []Message, opts LLMOptions) (string, error)
}

// STTOptions holds configurable parameters for speech-to-text.
type STTOptions struct {
	Model    string // model identifier (e.g. "whisper-1", "whisper-large-v3-turbo")
	Prompt   string // initial prompt / custom dictionary for context
	Language string // ISO language code or "" for auto-detection
}

// LLMOptions holds configurable parameters for LLM chat completion.
type LLMOptions struct {
	Model       string  // model identifier (e.g. "gpt-4o-mini", "claude-sonnet-4-20250514")
	Temperature float64 // sampling temperature (0.0–2.0)
	MaxTokens   int     // maximum tokens in the response
	TopP        float64 // nucleus sampling threshold
}

// Message is a chat message with a role and content.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// DefaultLLMOptions returns sensible defaults for LLM calls.
func DefaultLLMOptions() LLMOptions {
	return LLMOptions{
		Temperature: 0.3,
		MaxTokens:   2048,
		TopP:        0.95,
	}
}
