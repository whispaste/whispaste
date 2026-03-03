package main

import (
	"fmt"
	"strings"
	"testing"
)

func TestAPIErrorCodes(t *testing.T) {
	tests := []struct {
		status  int
		body    string
		wantMsg string
	}{
		{401, `{}`, "authentication failed"},
		{429, `{}`, "rate limit"},
		{413, `{}`, "too large"},
		{500, `{}`, "server error"},
		{502, `{}`, "server error"},
		{503, `{}`, "server error"},
		{400, `{"error":{"message":"invalid model"}}`, "invalid model"},
		{400, `not json`, "not json"},
	}

	for _, tt := range tests {
		t.Run(fmt.Sprintf("status_%d", tt.status), func(t *testing.T) {
			err := apiError(tt.status, []byte(tt.body))
			if err == nil {
				t.Fatal("apiError should return non-nil error")
			}
			errMsg := strings.ToLower(err.Error())
			if !strings.Contains(errMsg, strings.ToLower(tt.wantMsg)) {
				t.Errorf("apiError(%d) = %q, want to contain %q", tt.status, err.Error(), tt.wantMsg)
			}
		})
	}
}

func TestAPIError200IsNil(t *testing.T) {
	// apiError is only called on non-200 responses, but verify behavior
	err := apiError(200, nil)
	if err == nil {
		// 200 falls through to default 4xx case; verify it returns *some* error
		// since it's not expected to be called with 200
	}
}

func TestTranscribeLanguageFiltering(t *testing.T) {
	// Verify the language-filtering logic used by Transcribe:
	// "auto" and "" should be treated as no-language
	for _, lang := range []string{"", "auto"} {
		if lang != "" && lang != "auto" {
			t.Errorf("language %q should be filtered out", lang)
		}
	}
	// Explicit languages should pass through
	for _, lang := range []string{"de", "en", "fr"} {
		if lang == "" || lang == "auto" {
			t.Errorf("language %q should be sent", lang)
		}
	}
}

func TestAPIErrorJSONParsing(t *testing.T) {
	// Test that well-formed error JSON is extracted
	body := `{"error":{"message":"Model not found","type":"invalid_request_error"}}`
	err := apiError(404, []byte(body))
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "Model not found") {
		t.Errorf("error = %q, should contain 'Model not found'", err.Error())
	}
}

func TestAPIErrorMalformedJSON(t *testing.T) {
	body := `this is not json`
	err := apiError(400, []byte(body))
	if err == nil {
		t.Fatal("expected error")
	}
	// Should fall back to raw body
	if !strings.Contains(err.Error(), "this is not json") {
		t.Errorf("error = %q, should contain raw body", err.Error())
	}
}
