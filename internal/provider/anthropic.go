package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// AnthropicLLM handles chat completion via the Anthropic Messages API.
// Anthropic uses a different format than OpenAI: separate "system" parameter,
// "x-api-key" header instead of Bearer auth, and "max_tokens" is required.
type AnthropicLLM struct {
	APIKey       string
	DefaultModel string // e.g. "claude-sonnet-4-20250514"
}

func (p *AnthropicLLM) Name() string { return "anthropic" }

func (p *AnthropicLLM) ChatCompletion(ctx context.Context, messages []Message, opts LLMOptions) (string, error) {
	model := opts.Model
	if model == "" {
		model = p.DefaultModel
	}
	maxTokens := opts.MaxTokens
	if maxTokens <= 0 {
		maxTokens = 2048
	}

	// Anthropic separates system messages from the conversation
	var systemPrompt string
	var userMessages []map[string]string
	for _, m := range messages {
		if m.Role == "system" {
			systemPrompt = m.Content
			continue
		}
		userMessages = append(userMessages, map[string]string{
			"role":    m.Role,
			"content": m.Content,
		})
	}

	reqBody := map[string]interface{}{
		"model":      model,
		"max_tokens": maxTokens,
		"messages":   userMessages,
	}
	if systemPrompt != "" {
		reqBody["system"] = systemPrompt
	}
	if opts.Temperature >= 0 {
		reqBody["temperature"] = opts.Temperature
	}
	if opts.TopP > 0 && opts.TopP < 1.0 {
		reqBody["top_p"] = opts.TopP
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	client := &http.Client{Timeout: 60 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "POST",
		"https://api.anthropic.com/v1/messages", bytes.NewReader(jsonData))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("x-api-key", p.APIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("anthropic-version", "2023-06-01")

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
		return "", parseAPIError("anthropic", resp.StatusCode, respBody)
	}

	// Anthropic response format: { content: [{ type: "text", text: "..." }] }
	var result struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}
	for _, block := range result.Content {
		if block.Type == "text" && block.Text != "" {
			return block.Text, nil
		}
	}
	return "", fmt.Errorf("anthropic returned empty response")
}
