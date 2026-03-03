package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// smartModePresets maps preset names to system prompts.
var smartModePresets = map[string]string{
	"cleanup": "Clean up the following dictated text. Fix grammar, punctuation, and capitalization. Remove filler words. Keep the original language and meaning. Return only the cleaned text.",
	"email":   "Rewrite the following dictated text as a professional email. Use proper greeting and closing. Fix grammar and punctuation. Keep the original language. Return only the email text.",
	"bullets": "Rewrite the following dictated text as a structured bullet-point list. Fix grammar and punctuation. Keep the original language. Return only the bullet list.",
	"formal":  "Rewrite the following dictated text in formal, professional language. Fix grammar and punctuation. Keep the original language. Return only the rewritten text.",
}

// PostProcess sends transcribed text through GPT-4o-mini for formatting/cleanup.
// endpoint should be the base API URL (e.g. "https://api.openai.com/v1").
func PostProcess(text, preset, customPrompt, targetLang, apiKey, endpoint string) (string, error) {
	systemPrompt := buildSmartPrompt(preset, customPrompt, targetLang)
	if systemPrompt == "" {
		return text, nil
	}

	chatURL := "https://api.openai.com/v1/chat/completions"
	if endpoint != "" {
		// Strip /audio/transcriptions suffix if present to get base URL
		base := endpoint
		if idx := len(base) - len("/audio/transcriptions"); idx > 0 && base[idx:] == "/audio/transcriptions" {
			base = base[:idx]
		}
		chatURL = base + "/chat/completions"
	}

	reqBody := map[string]interface{}{
		"model": "gpt-4o-mini",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": text},
		},
		"temperature": 0.3,
		"max_tokens":  2048,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return text, fmt.Errorf("failed to marshal request: %w", err)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return text, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return text, fmt.Errorf("smart mode request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return text, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return text, fmt.Errorf("smart mode API error %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return text, fmt.Errorf("failed to parse response: %w", err)
	}
	if len(result.Choices) == 0 || result.Choices[0].Message.Content == "" {
		return text, fmt.Errorf("empty response from smart mode")
	}
	return result.Choices[0].Message.Content, nil
}

func buildSmartPrompt(preset, customPrompt, targetLang string) string {
	if preset == "translate" {
		if targetLang == "" {
			targetLang = "English"
		}
		return fmt.Sprintf("Translate the following text to %s. Return only the translation, no explanations.", targetLang)
	}
	if preset == "custom" && customPrompt != "" {
		return customPrompt
	}
	if p, ok := smartModePresets[preset]; ok {
		return p
	}
	return ""
}
