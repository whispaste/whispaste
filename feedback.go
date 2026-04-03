package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

var (
	lastFeedbackMu   sync.Mutex
	lastFeedbackTime time.Time
)

type feedbackPayload struct {
	Rating     int    `json:"rating"`
	Text       string `json:"text,omitempty"`
	AppVersion string `json:"app_version"`
	DeviceID   string `json:"device_id"`
}

// submitFeedback sends user feedback to the relay endpoint.
// Rate-limited to once per 24 hours locally.
func submitFeedback(rating int, text string) error {
	text = strings.TrimSpace(text)
	if len([]rune(text)) > 500 {
		text = string([]rune(text)[:500])
	}

	if FeedbackRelayURL == "" {
		return fmt.Errorf("feedback relay not configured")
	}
	if rating < 1 || rating > 5 {
		return fmt.Errorf("invalid rating: %d", rating)
	}

	lastFeedbackMu.Lock()
	if time.Since(lastFeedbackTime) < 24*time.Hour {
		lastFeedbackMu.Unlock()
		return fmt.Errorf("rate limited: one feedback per 24 hours")
	}
	lastFeedbackTime = time.Now()
	lastFeedbackMu.Unlock()

	payload := feedbackPayload{
		Rating:     rating,
		Text:       text,
		AppVersion: AppVersion,
		DeviceID:   deriveDeviceID(),
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal feedback: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, "POST", FeedbackRelayURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("send feedback: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 429 {
		return fmt.Errorf("rate limited by server")
	}
	if resp.StatusCode >= 300 {
		return fmt.Errorf("server error: %d", resp.StatusCode)
	}

	logInfo("Feedback submitted: %d stars", rating)
	return nil
}
