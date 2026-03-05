package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"
)

// Transcribe sends audio to the Whisper-compatible API and returns the transcription.
func Transcribe(audioWAV []byte, language string, apiKey string, model string, endpoint string, prompt string) (string, error) {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)

	part, err := writer.CreateFormFile("file", "audio.wav")
	if err != nil {
		return "", fmt.Errorf("failed to create form file: %w", err)
	}
	if _, err := part.Write(audioWAV); err != nil {
		return "", fmt.Errorf("failed to write audio data: %w", err)
	}

	if err := writer.WriteField("model", model); err != nil {
		return "", fmt.Errorf("failed to write model field: %w", err)
	}
	if language != "" && language != "auto" {
		if err := writer.WriteField("language", language); err != nil {
			return "", fmt.Errorf("failed to write language field: %w", err)
		}
	}
	if prompt != "" {
		if err := writer.WriteField("prompt", prompt); err != nil {
			return "", fmt.Errorf("failed to write prompt field: %w", err)
		}
	}
	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("failed to finalize request body: %w", err)
	}

	if endpoint == "" {
		endpoint = "https://api.openai.com/v1/audio/transcriptions"
	}

	logInfo("API transcription: model=%s audioSize=%d", model, len(audioWAV))

	start := time.Now()
	// Dynamic timeout: 60s base + 30s per MB of audio data
	timeout := 60*time.Second + time.Duration(len(audioWAV)/(1024*1024))*30*time.Second
	client := &http.Client{Timeout: timeout}
	req, err := http.NewRequest("POST", endpoint, &body)
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := client.Do(req)
	if err != nil {
		logError("API transcription failed: model=%s err=%v", model, err)
		return "", fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		logError("API transcription read failed: model=%s err=%v", model, err)
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		apiErr := apiError(resp.StatusCode, respBody)
		logError("API transcription error: model=%s status=%d err=%v", model, resp.StatusCode, apiErr)
		return "", apiErr
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}
	logInfo("API transcription complete: model=%s duration=%v textLen=%d", model, time.Since(start), len(result.Text))
	return result.Text, nil
}

func apiError(status int, body []byte) error {
	switch status {
	case 401:
		return fmt.Errorf("API authentication failed – check your API key")
	case 429:
		return fmt.Errorf("API rate limit exceeded – please wait and try again")
	case 413:
		return fmt.Errorf("audio file too large for the API")
	default:
		if status >= 500 {
			return fmt.Errorf("OpenAI server error (%d) – try again later", status)
		}
		// Try to extract error message from JSON response
		var errResp struct {
			Error struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		if json.Unmarshal(body, &errResp) == nil && errResp.Error.Message != "" {
			return fmt.Errorf("API error %d: %s", status, errResp.Error.Message)
		}
		return fmt.Errorf("API error %d: %s", status, string(body))
	}
}
