package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// OpenAICompatSTT handles transcription for any OpenAI-compatible speech API.
// Works with OpenAI, Groq, and other providers using the same multipart format.
type OpenAICompatSTT struct {
	ProviderName string // "openai", "groq"
	Endpoint     string // full URL (e.g. "https://api.groq.com/openai/v1/audio/transcriptions")
	APIKey       string
	DefaultModel string // fallback model if opts.Model is empty
}

var multiSpaceRe = regexp.MustCompile(`\s{2,}`)

func normalizeText(text string) string {
	text = strings.ReplaceAll(text, "\r\n", " ")
	text = strings.ReplaceAll(text, "\n", " ")
	text = multiSpaceRe.ReplaceAllString(text, " ")
	return strings.TrimSpace(text)
}

func (p *OpenAICompatSTT) Name() string { return p.ProviderName }

func (p *OpenAICompatSTT) Transcribe(ctx context.Context, audio []byte, lang string, opts STTOptions) (string, error) {
	model := opts.Model
	if model == "" {
		model = p.DefaultModel
	}

	var bodyBuf bytes.Buffer
	writer := multipart.NewWriter(&bodyBuf)

	part, err := writer.CreateFormFile("file", "audio.wav")
	if err != nil {
		return "", fmt.Errorf("create form file: %w", err)
	}
	if _, err := part.Write(audio); err != nil {
		return "", fmt.Errorf("write audio data: %w", err)
	}
	if err := writer.WriteField("model", model); err != nil {
		return "", fmt.Errorf("write model field: %w", err)
	}
	if lang != "" && lang != "auto" {
		if err := writer.WriteField("language", lang); err != nil {
			return "", fmt.Errorf("write language field: %w", err)
		}
	}
	if opts.Prompt != "" {
		if err := writer.WriteField("prompt", opts.Prompt); err != nil {
			return "", fmt.Errorf("write prompt field: %w", err)
		}
	}
	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("finalize request body: %w", err)
	}

	// Dynamic timeout: 60s base + 30s per MB of audio
	timeout := 60*time.Second + time.Duration(len(audio)/(1024*1024))*30*time.Second
	client := &http.Client{Timeout: timeout}

	req, err := http.NewRequestWithContext(ctx, "POST", p.Endpoint, bytes.NewReader(bodyBuf.Bytes()))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+p.APIKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", parseAPIError(p.ProviderName, resp.StatusCode, respBody)
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}
	return normalizeText(result.Text), nil
}

// OpenAICompatLLM handles chat completion for any OpenAI-compatible API.
// Works with OpenAI, Groq, Gemini, and other compatible providers.
type OpenAICompatLLM struct {
	ProviderName string // "openai", "groq", "gemini"
	Endpoint     string // full URL (e.g. "https://api.groq.com/openai/v1/chat/completions")
	APIKey       string
	DefaultModel string // fallback model if opts.Model is empty
}

func (p *OpenAICompatLLM) Name() string { return p.ProviderName }

func (p *OpenAICompatLLM) ChatCompletion(ctx context.Context, messages []Message, opts LLMOptions) (string, error) {
	model := opts.Model
	if model == "" {
		model = p.DefaultModel
	}

	reqBody := map[string]interface{}{
		"model":    model,
		"messages": messages,
	}
	if opts.Temperature >= 0 {
		reqBody["temperature"] = opts.Temperature
	}
	if opts.MaxTokens > 0 {
		reqBody["max_tokens"] = opts.MaxTokens
	}
	if opts.TopP > 0 && opts.TopP < 1.0 {
		reqBody["top_p"] = opts.TopP
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	client := &http.Client{Timeout: 60 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "POST", p.Endpoint, bytes.NewReader(jsonData))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+p.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", parseAPIError(p.ProviderName, resp.StatusCode, respBody)
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}
	if len(result.Choices) == 0 || result.Choices[0].Message.Content == "" {
		return "", fmt.Errorf("%s returned empty response", p.ProviderName)
	}
	return result.Choices[0].Message.Content, nil
}

// parseAPIError creates a descriptive error from an API error response.
func parseAPIError(provider string, status int, body []byte) error {
	switch status {
	case 401:
		return fmt.Errorf("%s: authentication failed — check your API key", provider)
	case 429:
		return fmt.Errorf("%s: rate limit exceeded — please wait and try again", provider)
	case 413:
		return fmt.Errorf("%s: request too large", provider)
	}
	if status >= 500 {
		return fmt.Errorf("%s: server error (%d) — try again later", provider, status)
	}
	var errResp struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &errResp) == nil && errResp.Error.Message != "" {
		return fmt.Errorf("%s error %d: %s", provider, status, errResp.Error.Message)
	}
	// Don't expose raw response body — may contain sensitive provider details
	bodyStr := string(body)
	if len(bodyStr) > 200 {
		bodyStr = bodyStr[:200] + "…"
	}
	return fmt.Errorf("%s error %d: %s", provider, status, bodyStr)
}
