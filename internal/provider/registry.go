package provider

import "fmt"

// Cloud STT provider endpoint and model defaults.
const (
	OpenAISTTEndpoint = "https://api.openai.com/v1/audio/transcriptions"
	OpenAISTTModel    = "whisper-1"

	GroqSTTEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
	GroqSTTModel    = "whisper-large-v3-turbo"

	// LLM endpoints
	OpenAILLMEndpoint = "https://api.openai.com/v1/chat/completions"
	OpenAILLMModel    = "gpt-4o-mini"

	GroqLLMEndpoint = "https://api.groq.com/openai/v1/chat/completions"
	GroqLLMModel    = "llama-3.3-70b-versatile"

	GeminiLLMEndpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
	GeminiLLMModel    = "gemini-2.5-flash"

	AnthropicLLMModel = "claude-sonnet-4-20250514"

	DeepgramSTTModel = "nova-2"
)

// STTProviderInfo describes a cloud STT provider for UI display.
type STTProviderInfo struct {
	ID           string   // "openai", "groq", "deepgram"
	Name         string   // Display name
	Models       []string // Available model IDs
	DefaultModel string
	NeedsAPIKey  string // Config field name for the API key
}

// LLMProviderInfo describes a cloud LLM provider for UI display.
type LLMProviderInfo struct {
	ID           string   // "openai", "anthropic", "gemini", "groq"
	Name         string   // Display name
	Models       []string // Available model IDs
	DefaultModel string
	NeedsAPIKey  string // Config field name for the API key
}

// CloudSTTProviders lists all supported cloud STT providers.
var CloudSTTProviders = []STTProviderInfo{
	{
		ID:           "openai",
		Name:         "OpenAI",
		Models:       []string{"whisper-1", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"},
		DefaultModel: OpenAISTTModel,
		NeedsAPIKey:  "api_key",
	},
	{
		ID:           "groq",
		Name:         "Groq",
		Models:       []string{"whisper-large-v3-turbo", "whisper-large-v3"},
		DefaultModel: GroqSTTModel,
		NeedsAPIKey:  "groq_api_key",
	},
	{
		ID:           "deepgram",
		Name:         "Deepgram",
		Models:       []string{"nova-2", "nova-3"},
		DefaultModel: DeepgramSTTModel,
		NeedsAPIKey:  "deepgram_api_key",
	},
}

// CloudLLMProviders lists all supported cloud LLM providers.
var CloudLLMProviders = []LLMProviderInfo{
	{
		ID:           "openai",
		Name:         "OpenAI",
		Models:       []string{"gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1-nano"},
		DefaultModel: OpenAILLMModel,
		NeedsAPIKey:  "api_key",
	},
	{
		ID:           "anthropic",
		Name:         "Anthropic",
		Models:       []string{"claude-sonnet-4-20250514", "claude-haiku-3-5-20241022"},
		DefaultModel: AnthropicLLMModel,
		NeedsAPIKey:  "anthropic_api_key",
	},
	{
		ID:           "gemini",
		Name:         "Google Gemini",
		Models:       []string{"gemini-2.5-flash", "gemini-2.0-flash-lite"},
		DefaultModel: GeminiLLMModel,
		NeedsAPIKey:  "gemini_api_key",
	},
	{
		ID:           "groq",
		Name:         "Groq",
		Models:       []string{"llama-3.3-70b-versatile", "gemma2-9b-it"},
		DefaultModel: GroqLLMModel,
		NeedsAPIKey:  "groq_api_key",
	},
}

// NewCloudSTT creates an STTProvider for the given provider name.
func NewCloudSTT(providerID, apiKey string) (STTProvider, error) {
	switch providerID {
	case "openai", "":
		return &OpenAICompatSTT{
			ProviderName: "openai",
			Endpoint:     OpenAISTTEndpoint,
			APIKey:       apiKey,
			DefaultModel: OpenAISTTModel,
		}, nil
	case "groq":
		return &OpenAICompatSTT{
			ProviderName: "groq",
			Endpoint:     GroqSTTEndpoint,
			APIKey:       apiKey,
			DefaultModel: GroqSTTModel,
		}, nil
	case "deepgram":
		return &DeepgramSTT{
			APIKey:       apiKey,
			DefaultModel: DeepgramSTTModel,
		}, nil
	default:
		return nil, fmt.Errorf("unknown STT provider: %s", providerID)
	}
}

// NewCloudLLM creates an LLMProvider for the given provider name.
func NewCloudLLM(providerID, apiKey string) (LLMProvider, error) {
	switch providerID {
	case "openai", "", "cloud":
		return &OpenAICompatLLM{
			ProviderName: "openai",
			Endpoint:     OpenAILLMEndpoint,
			APIKey:       apiKey,
			DefaultModel: OpenAILLMModel,
		}, nil
	case "anthropic":
		return &AnthropicLLM{
			APIKey:       apiKey,
			DefaultModel: AnthropicLLMModel,
		}, nil
	case "gemini":
		return &OpenAICompatLLM{
			ProviderName: "gemini",
			Endpoint:     GeminiLLMEndpoint,
			APIKey:       apiKey,
			DefaultModel: GeminiLLMModel,
		}, nil
	case "groq":
		return &OpenAICompatLLM{
			ProviderName: "groq",
			Endpoint:     GroqLLMEndpoint,
			APIKey:       apiKey,
			DefaultModel: GroqLLMModel,
		}, nil
	default:
		return nil, fmt.Errorf("unknown LLM provider: %s", providerID)
	}
}

// NewCustomSTT creates an STTProvider for a user-defined OpenAI-compatible endpoint.
func NewCustomSTT(endpoint, apiKey, model string) STTProvider {
	return &OpenAICompatSTT{
		ProviderName: "custom",
		Endpoint:     endpoint,
		APIKey:       apiKey,
		DefaultModel: model,
	}
}

// NewCustomLLM creates an LLMProvider for a user-defined OpenAI-compatible endpoint.
func NewCustomLLM(endpoint, apiKey, model string) LLMProvider {
	return &OpenAICompatLLM{
		ProviderName: "custom",
		Endpoint:     endpoint,
		APIKey:       apiKey,
		DefaultModel: model,
	}
}
