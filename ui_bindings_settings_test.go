package main

import (
	"strings"
	"testing"

	"github.com/whispaste/whispaste/internal/models"
	"github.com/whispaste/whispaste/internal/provider"
)

func TestAvailableModelEntriesUsesSelectedCloudProviderKey(t *testing.T) {
	cfg := &Config{
		CloudSTTProvider: "groq",
		GroqAPIKey:       "groq-secret",
		Model:            "",
	}

	downloaded := []models.Info{
		{ID: "whisper-small", Name: "Whisper Small", Size: "181MB"},
	}

	got := availableModelEntries(cfg, downloaded)
	if len(got) != 2 {
		t.Fatalf("len(availableModelEntries) = %d, want 2", len(got))
	}
	if got[0].IsLocal {
		t.Fatalf("first entry should be cloud, got local")
	}
	if got[0].ID != "whisper-large-v3-turbo" {
		t.Fatalf("cloud model ID = %q, want %q", got[0].ID, "whisper-large-v3-turbo")
	}
	if !strings.Contains(got[0].Name, "Groq") {
		t.Fatalf("cloud model name = %q, want provider label containing %q", got[0].Name, "Groq")
	}
	if !got[1].IsLocal || got[1].ID != "whisper-small" {
		t.Fatalf("second entry = %#v, want local whisper-small", got[1])
	}
}

func TestAvailableModelEntriesOmitsCloudWithoutSelectedProviderKey(t *testing.T) {
	cfg := &Config{
		CloudSTTProvider: "deepgram",
		APIKey:           "openai-only",
		DeepgramAPIKey:   "",
		Model:            "nova-2",
	}

	got := availableModelEntries(cfg, nil)
	if len(got) != 0 {
		t.Fatalf("len(availableModelEntries) = %d, want 0 when selected provider has no API key", len(got))
	}
}

func TestCreateSelectedCloudSTTUsesSelectedProviderKeyAndDefaultModel(t *testing.T) {
	cfg := &Config{
		CloudSTTProvider: "deepgram",
		DeepgramAPIKey:   "deepgram-secret",
	}

	stt, model, err := createSelectedCloudSTT(cfg, "")
	if err != nil {
		t.Fatalf("createSelectedCloudSTT returned error: %v", err)
	}
	if model != provider.DeepgramSTTModel {
		t.Fatalf("model = %q, want %q", model, provider.DeepgramSTTModel)
	}
	if _, ok := stt.(*provider.DeepgramSTT); !ok {
		t.Fatalf("provider type = %T, want *provider.DeepgramSTT", stt)
	}
}

func TestCreateSelectedCloudSTTOverrideKey(t *testing.T) {
	cfg := &Config{
		CloudSTTProvider: "groq",
		GroqAPIKey:       "saved-key",
		Model:            "whisper-large-v3",
	}

	stt, model, err := createSelectedCloudSTT(cfg, "override-key")
	if err != nil {
		t.Fatalf("createSelectedCloudSTT returned error: %v", err)
	}
	if model != "whisper-large-v3" {
		t.Fatalf("model = %q, want %q", model, "whisper-large-v3")
	}
	got, ok := stt.(*provider.OpenAICompatSTT)
	if !ok {
		t.Fatalf("provider type = %T, want *provider.OpenAICompatSTT", stt)
	}
	if got.APIKey != "override-key" {
		t.Fatalf("APIKey = %q, want override-key", got.APIKey)
	}
}
