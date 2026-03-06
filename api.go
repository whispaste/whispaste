package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"strings"
	"time"
)

const (
	maxRetries    = 3
	retryBaseWait = 2 * time.Second
)

// Transcribe sends audio to the Whisper-compatible API and returns the transcription.
// It retries transient errors (DNS, timeout, 5xx, 429) with exponential backoff.
func Transcribe(ctx context.Context, audioWAV []byte, language string, apiKey string, model string, endpoint string, prompt string) (string, error) {
	// Build the multipart body once — we'll replay it via bytes.NewReader on retries
	var bodyBuf bytes.Buffer
	writer := multipart.NewWriter(&bodyBuf)

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

	contentType := writer.FormDataContentType()
	bodyBytes := bodyBuf.Bytes()

	logInfo("API transcription: model=%s audioSize=%d", model, len(audioWAV))
	start := time.Now()

	// Dynamic timeout per attempt: 60s base + 30s per MB of audio data
	timeout := 60*time.Second + time.Duration(len(audioWAV)/(1024*1024))*30*time.Second

	var lastErr error
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			wait := retryBaseWait * (1 << (attempt - 1)) // 2s, 4s, 8s
			logWarn("API retry %d/%d after %v (previous: %v)", attempt, maxRetries, wait, lastErr)
			select {
			case <-ctx.Done():
				return "", fmt.Errorf("transcription cancelled: %w", ctx.Err())
			case <-time.After(wait):
			}
		}

		text, err, retryable := doTranscribeAttempt(ctx, bodyBytes, contentType, endpoint, apiKey, model, timeout)
		if err == nil {
			if attempt > 0 {
				logInfo("API transcription succeeded on retry %d", attempt)
			}
			logInfo("API transcription complete: model=%s duration=%v textLen=%d", model, time.Since(start), len(text))
			return text, nil
		}
		lastErr = err
		if !retryable {
			return "", err
		}
	}

	logError("API transcription failed after %d retries: %v", maxRetries, lastErr)
	return "", lastErr
}

// doTranscribeAttempt performs a single API call. Returns (text, error, retryable).
func doTranscribeAttempt(ctx context.Context, body []byte, contentType, endpoint, apiKey, model string, timeout time.Duration) (string, error, bool) {
	client := &http.Client{Timeout: timeout}
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err), false
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", contentType)

	resp, err := client.Do(req)
	if err != nil {
		logError("API transcription failed: model=%s err=%v", model, err)
		return "", fmt.Errorf("request failed: %w", err), isRetryableError(err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		logError("API transcription read failed: model=%s err=%v", model, err)
		return "", fmt.Errorf("failed to read response: %w", err), true
	}

	if resp.StatusCode != http.StatusOK {
		apiErr := apiError(resp.StatusCode, respBody)
		logError("API transcription error: model=%s status=%d err=%v", model, resp.StatusCode, apiErr)
		return "", apiErr, isRetryableStatus(resp.StatusCode)
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err), false
	}
	return result.Text, nil, false
}

// isRetryableError checks if a network-level error is transient.
func isRetryableError(err error) bool {
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		return false // user-initiated cancel or parent context timeout
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true // timeout, DNS, connection refused
	}
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return true
	}
	// Catch common transient error messages
	msg := err.Error()
	if strings.Contains(msg, "no such host") ||
		strings.Contains(msg, "connection refused") ||
		strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "i/o timeout") {
		return true
	}
	return false
}

// isRetryableStatus checks if an HTTP status code indicates a transient server error.
func isRetryableStatus(status int) bool {
	return status == 429 || status >= 500
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

// TestAPIKey validates an API key by making a lightweight GET request to the models endpoint.
func TestAPIKey(apiKey, endpoint string) error {
	if apiKey == "" {
		return fmt.Errorf("API key is empty")
	}
	base := endpoint
	if base == "" {
		base = "https://api.openai.com/v1"
	}
	base = strings.TrimSuffix(base, "/")
	url := base + "/models"

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return fmt.Errorf("request creation failed: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("connection failed: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	if resp.StatusCode == 401 {
		return fmt.Errorf("invalid API key")
	}
	if resp.StatusCode >= 400 {
		return fmt.Errorf("API returned status %d", resp.StatusCode)
	}
	return nil
}
