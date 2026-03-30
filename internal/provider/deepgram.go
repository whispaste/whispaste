package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// DeepgramSTT handles transcription via the Deepgram Nova API.
// Deepgram uses a different format: raw audio body (not multipart),
// query parameters for options, and "Token" auth header.
type DeepgramSTT struct {
	APIKey       string
	DefaultModel string // e.g. "nova-2"
}

func (p *DeepgramSTT) Name() string { return "deepgram" }

func (p *DeepgramSTT) Transcribe(ctx context.Context, audio []byte, lang string, opts STTOptions) (string, error) {
	model := opts.Model
	if model == "" {
		model = p.DefaultModel
		if model == "" {
			model = "nova-2"
		}
	}

	// Build URL with properly encoded query parameters
	params := url.Values{}
	params.Set("model", model)
	params.Set("smart_format", "true")
	if lang != "" && lang != "auto" {
		params.Set("language", lang)
	}
	endpoint := "https://api.deepgram.com/v1/listen?" + params.Encode()

	// Dynamic timeout: 60s base + 30s per MB
	timeout := 60*time.Second + time.Duration(len(audio)/(1024*1024))*30*time.Second
	client := &http.Client{Timeout: timeout}

	// Deepgram accepts raw audio bytes, not multipart
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(audio))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Token "+p.APIKey)
	req.Header.Set("Content-Type", "audio/wav")

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
		return "", parseAPIError("deepgram", resp.StatusCode, respBody)
	}

	// Deepgram response: { results: { channels: [{ alternatives: [{ transcript: "..." }] }] } }
	var result struct {
		Results struct {
			Channels []struct {
				Alternatives []struct {
					Transcript string `json:"transcript"`
				} `json:"alternatives"`
			} `json:"channels"`
		} `json:"results"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}

	if len(result.Results.Channels) > 0 && len(result.Results.Channels[0].Alternatives) > 0 {
		return normalizeText(result.Results.Channels[0].Alternatives[0].Transcript), nil
	}
	return "", fmt.Errorf("deepgram returned empty transcription")
}
