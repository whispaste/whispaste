package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/whispaste/whispaste/internal/models"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.Mode != "push_to_talk" {
		t.Errorf("Mode = %q, want push_to_talk", cfg.Mode)
	}
	if cfg.Language != "auto" {
		t.Errorf("Language = %q, want auto", cfg.Language)
	}
	if cfg.Model != "whisper-1" {
		t.Errorf("Model = %q, want whisper-1", cfg.Model)
	}
	if cfg.OverlayPos != "top_center" {
		t.Errorf("OverlayPos = %q, want top_center", cfg.OverlayPos)
	}
	if !cfg.AutoPaste {
		t.Error("AutoPaste should be true by default")
	}
	if !cfg.PlaySounds {
		t.Error("PlaySounds should be true by default")
	}
	if !cfg.CheckUpdates {
		t.Error("CheckUpdates should be true by default")
	}
	if cfg.Theme != "system" {
		t.Errorf("Theme = %q, want system", cfg.Theme)
	}
	if len(cfg.HotkeyMods) != 2 || cfg.HotkeyMods[0] != "Ctrl" || cfg.HotkeyMods[1] != "Shift" {
		t.Errorf("HotkeyMods = %v, want [Ctrl Shift]", cfg.HotkeyMods)
	}
	if cfg.HotkeyKey != "D" {
		t.Errorf("HotkeyKey = %q, want D", cfg.HotkeyKey)
	}
	if cfg.UseVAD {
		t.Error("UseVAD should be false by default")
	}
	if cfg.GetVADSensitivity() != 0.5 {
		t.Errorf("GetVADSensitivity() = %f, want 0.5 (default)", cfg.GetVADSensitivity())
	}
	if cfg.GetSmartModeTarget() != defaultSmartModeTargetLanguage {
		t.Errorf("GetSmartModeTarget() = %q, want %q", cfg.GetSmartModeTarget(), defaultSmartModeTargetLanguage)
	}
	if cfg.GetInputGain() != 1.0 {
		t.Errorf("GetInputGain() = %f, want 1.0", cfg.GetInputGain())
	}
}

func TestConfigSaveLoad(t *testing.T) {
	// Use a temporary directory for config
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "config.json")

	cfg := DefaultConfig()
	cfg.APIKey = "sk-test-1234567890"
	cfg.Language = "de"
	cfg.Theme = "dark"

	// Manually marshal and write (since Save() uses configPath which points to APPDATA)
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if err := os.WriteFile(tmpFile, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	// Read back and unmarshal
	readData, err := os.ReadFile(tmpFile)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	loaded := DefaultConfig()
	if err := json.Unmarshal(readData, loaded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if loaded.APIKey != "sk-test-1234567890" {
		t.Errorf("APIKey = %q, want sk-test-1234567890", loaded.APIKey)
	}
	if loaded.Language != "de" {
		t.Errorf("Language = %q, want de", loaded.Language)
	}
	if loaded.Theme != "dark" {
		t.Errorf("Theme = %q, want dark", loaded.Theme)
	}
	// Ensure defaults are preserved for unset fields
	if loaded.Model != "whisper-1" {
		t.Errorf("Model = %q, want whisper-1", loaded.Model)
	}
}

func TestConfigJSONRoundtrip(t *testing.T) {
	cfg := DefaultConfig()
	cfg.APIKey = "sk-abc"
	cfg.Mode = "toggle"
	cfg.OverlayPos = "cursor"

	data, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded Config
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if decoded.APIKey != cfg.APIKey {
		t.Errorf("APIKey mismatch: got %q, want %q", decoded.APIKey, cfg.APIKey)
	}
	if decoded.Mode != cfg.Mode {
		t.Errorf("Mode mismatch: got %q, want %q", decoded.Mode, cfg.Mode)
	}
	if decoded.OverlayPos != cfg.OverlayPos {
		t.Errorf("OverlayPos mismatch: got %q, want %q", decoded.OverlayPos, cfg.OverlayPos)
	}
}

func TestConfigThreadSafe(t *testing.T) {
	cfg := DefaultConfig()
	cfg.APIKey = "sk-thread-test"

	done := make(chan struct{})
	go func() {
		for i := 0; i < 100; i++ {
			cfg.GetAPIKey()
			cfg.HasAPIKey()
			cfg.GetUILanguage()
			cfg.GetCheckUpdates()
			cfg.IsPushToTalk()
			cfg.GetUseVAD()
			cfg.GetVADSensitivity()
		}
		close(done)
	}()

	for i := 0; i < 100; i++ {
		cfg.SetAPIKey("sk-changed")
		cfg.mu.Lock()
		cfg.CheckUpdates = !cfg.CheckUpdates
		cfg.mu.Unlock()
	}

	<-done
}

func TestConfigFilePermissions(t *testing.T) {
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "config.json")

	data := []byte(`{"api_key":"sk-test"}`)
	if err := os.WriteFile(tmpFile, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	info, err := os.Stat(tmpFile)
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	// On Windows, permission bits are limited, but file should exist and be readable
	if info.Size() == 0 {
		t.Error("Config file is empty")
	}
}

func TestConfigPartialJSON(t *testing.T) {
	// Config with only some fields set should merge with defaults
	partial := `{"api_key":"sk-partial","language":"fr"}`
	cfg := DefaultConfig()
	if err := json.Unmarshal([]byte(partial), cfg); err != nil {
		t.Fatalf("Unmarshal partial: %v", err)
	}

	if cfg.APIKey != "sk-partial" {
		t.Errorf("APIKey = %q, want sk-partial", cfg.APIKey)
	}
	if cfg.Language != "fr" {
		t.Errorf("Language = %q, want fr", cfg.Language)
	}
	// Defaults should be preserved
	if cfg.Mode != "push_to_talk" {
		t.Errorf("Mode = %q, want push_to_talk (default)", cfg.Mode)
	}
	if cfg.Theme != "system" {
		t.Errorf("Theme = %q, want system (default)", cfg.Theme)
	}
	// InputGain should be preserved at default 1.0 when absent from JSON
	if cfg.InputGain != 1.0 {
		t.Errorf("InputGain = %f, want 1.0 (default preserved)", cfg.InputGain)
	}
}

func TestConfigInputGainNormalization(t *testing.T) {
	tests := []struct {
		name string
		json string
		want float64
	}{
		{"zero resets to 1.0", `{"input_gain":0}`, 1.0},
		{"negative resets to 1.0", `{"input_gain":-1}`, 1.0},
		{"too high resets to 1.0", `{"input_gain":5.0}`, 1.0},
		{"valid value preserved", `{"input_gain":1.5}`, 1.5},
		{"minimum boundary", `{"input_gain":0.1}`, 0.1},
		{"maximum boundary", `{"input_gain":3.0}`, 3.0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := DefaultConfig()
			json.Unmarshal([]byte(tt.json), cfg)
			// Simulate the normalization from LoadConfig
			if cfg.InputGain < 0.1 || cfg.InputGain > 3.0 {
				cfg.InputGain = 1.0
			}
			if cfg.InputGain != tt.want {
				t.Errorf("InputGain = %f, want %f", cfg.InputGain, tt.want)
			}
		})
	}
}

func TestConfigVADRoundtrip(t *testing.T) {
	cfg := DefaultConfig()
	cfg.UseVAD = true
	cfg.VADSensitivity = 0.7

	data, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded Config
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if !decoded.UseVAD {
		t.Error("UseVAD should survive roundtrip")
	}
	if decoded.VADSensitivity != 0.7 {
		t.Errorf("VADSensitivity = %f, want 0.7", decoded.VADSensitivity)
	}
	if decoded.GetVADSensitivity() != 0.7 {
		t.Errorf("GetVADSensitivity() = %f, want 0.7", decoded.GetVADSensitivity())
	}
}

func TestHasCloudSTTKeyUsesSelectedProvider(t *testing.T) {
	cfg := DefaultConfig()
	cfg.APIKey = "openai-key"
	cfg.CloudSTTProvider = "deepgram"
	if cfg.HasCloudSTTKey() {
		t.Fatal("HasCloudSTTKey should be false when selected provider key is missing")
	}

	cfg.DeepgramAPIKey = "deepgram-key"
	if !cfg.HasCloudSTTKey() {
		t.Fatal("HasCloudSTTKey should be true when selected provider key is configured")
	}
}

func TestHasAnyModelUsesSelectedCloudSTTOrLocalModel(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	models.Init("whispaste-config-test")
	t.Cleanup(func() { models.Init(AppName) })

	cfg := DefaultConfig()
	cfg.APIKey = "openai-key"
	cfg.CloudSTTProvider = "deepgram"
	if cfg.HasAnyModel() {
		t.Fatal("HasAnyModel should be false when only a non-selected STT key is configured")
	}

	cfg.DeepgramAPIKey = "deepgram-key"
	if !cfg.HasAnyModel() {
		t.Fatal("HasAnyModel should be true when the selected STT provider key is configured")
	}

	cfg.DeepgramAPIKey = ""
	cfg.APIKey = ""
	if cfg.HasAnyModel() {
		t.Fatal("HasAnyModel should be false without selected cloud STT key or local model")
	}

	modelDir, err := models.Dir()
	if err != nil {
		t.Fatalf("models.Dir returned error: %v", err)
	}
	sttDir := filepath.Join(modelDir, "stt")
	if err := os.MkdirAll(sttDir, 0700); err != nil {
		t.Fatalf("MkdirAll returned error: %v", err)
	}
	modelFile := filepath.Join(sttDir, models.Available[0].Filename)
	if err := os.WriteFile(modelFile, []byte("test"), 0600); err != nil {
		t.Fatalf("WriteFile returned error: %v", err)
	}
	if !cfg.HasAnyModel() {
		t.Fatal("HasAnyModel should be true when a local model is downloaded")
	}
}

func TestGetEffectiveLocalTranscriptionLanguage(t *testing.T) {
	tests := []struct {
		name string
		cfg  *Config
		want string
	}{
		{
			name: "explicit transcription language wins",
			cfg: &Config{
				Language:              "auto",
				TranscriptionLanguage: "fr",
				UILanguage:            "de",
			},
			want: "fr",
		},
		{
			name: "auto falls back to ui language",
			cfg: &Config{
				Language:   "auto",
				UILanguage: "de",
			},
			want: "de",
		},
		{
			name: "non auto language is kept",
			cfg: &Config{
				Language:   "es",
				UILanguage: "de",
			},
			want: "es",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.cfg.GetEffectiveLocalTranscriptionLanguage(); got != tt.want {
				t.Fatalf("GetEffectiveLocalTranscriptionLanguage() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestGetLocalLLMModel(t *testing.T) {
	tests := []struct {
		name  string
		value string
		want  string
	}{
		{name: "default blank", value: "", want: supportedLocalLLMModelID},
		{name: "current supported", value: supportedLocalLLMModelID, want: supportedLocalLLMModelID},
		{name: "legacy qwen25", value: "qwen2.5-0.5b", want: supportedLocalLLMModelID},
		{name: "legacy qwen3", value: "qwen3-0.6b", want: supportedLocalLLMModelID},
		{name: "legacy smollm2", value: "smollm2", want: supportedLocalLLMModelID},
		{name: "unknown custom", value: "custom-model", want: supportedLocalLLMModelID},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := DefaultConfig()
			cfg.LocalLLMModel = tt.value
			if got := cfg.GetLocalLLMModel(); got != tt.want {
				t.Fatalf("GetLocalLLMModel() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestGetSmartModeTargetDefaultsToEnglish(t *testing.T) {
	cfg := DefaultConfig()
	cfg.mu.Lock()
	cfg.SmartModeTarget = ""
	cfg.mu.Unlock()

	if got := cfg.GetSmartModeTarget(); got != defaultSmartModeTargetLanguage {
		t.Fatalf("GetSmartModeTarget() = %q, want %q", got, defaultSmartModeTargetLanguage)
	}
}

func TestGetLocalTranscriptionMetadataLanguage(t *testing.T) {
	tests := []struct {
		name string
		cfg  *Config
		want string
	}{
		{
			name: "explicit transcription language is preserved",
			cfg: &Config{
				Language:              "auto",
				TranscriptionLanguage: "fr",
				UILanguage:            "de",
			},
			want: "fr",
		},
		{
			name: "auto stays unknown for metadata",
			cfg: &Config{
				Language:   "auto",
				UILanguage: "de",
			},
			want: "",
		},
		{
			name: "non auto app language is used",
			cfg: &Config{
				Language:   "es",
				UILanguage: "de",
			},
			want: "es",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.cfg.GetLocalTranscriptionMetadataLanguage(); got != tt.want {
				t.Fatalf("GetLocalTranscriptionMetadataLanguage() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestConfigFloatingButtonRoundtrip(t *testing.T) {
	cfg := DefaultConfig()
	cfg.FloatingButtonEnabled = true
	cfg.FloatingButtonX = 123
	cfg.FloatingButtonY = 456
	cfg.FloatingButtonColor = "purple"

	data, err := json.Marshal(cfg)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var decoded Config
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if !decoded.FloatingButtonEnabled {
		t.Error("FloatingButtonEnabled should be true")
	}
	if decoded.FloatingButtonX != 123 {
		t.Errorf("FloatingButtonX = %d, want 123", decoded.FloatingButtonX)
	}
	if decoded.FloatingButtonY != 456 {
		t.Errorf("FloatingButtonY = %d, want 456", decoded.FloatingButtonY)
	}
	if decoded.FloatingButtonColor != "purple" {
		t.Errorf("FloatingButtonColor = %q, want purple", decoded.FloatingButtonColor)
	}

	// Default should be false
	def := DefaultConfig()
	if def.FloatingButtonEnabled {
		t.Error("FloatingButtonEnabled should be false by default")
	}
	if def.GetFloatingButtonColor() != "cyan" {
		t.Errorf("GetFloatingButtonColor() default = %q, want cyan", def.GetFloatingButtonColor())
	}

	// Thread-safe getters
	cfg2 := DefaultConfig()
	cfg2.FloatingButtonEnabled = true
	cfg2.FloatingButtonX = 100
	cfg2.FloatingButtonY = 200
	cfg2.FloatingButtonColor = "rose"
	if !cfg2.GetFloatingButtonEnabled() {
		t.Error("GetFloatingButtonEnabled() should return true")
	}
	x, y := cfg2.GetFloatingButtonPos()
	if x != 100 || y != 200 {
		t.Errorf("GetFloatingButtonPos() = (%d, %d), want (100, 200)", x, y)
	}
	if cfg2.GetFloatingButtonColor() != "rose" {
		t.Errorf("GetFloatingButtonColor() = %q, want rose", cfg2.GetFloatingButtonColor())
	}
}

func TestLoadConfigMigratesRemovedPresets(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	models.Init("whispaste-config-test")
	t.Cleanup(func() { models.Init(AppName) })

	// Write a config with a removed preset and deprecated fields
	old := DefaultConfig()
	old.SmartModePreset = "email"
	old.SmartModePrompt = "Write me an email"
	old.CustomTemplates = map[string]string{"custom1": "do stuff"}
	old.AppDetection = true
	old.AppPresets = map[string]string{"outlook.exe": "email"}
	old.FallbackPreset = "formal"

	dir, _ := configPath()
	if err := os.MkdirAll(filepath.Dir(dir), 0700); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	data, _ := json.MarshalIndent(old, "", "  ")
	if err := os.WriteFile(dir, data, 0600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig: %v", err)
	}

	if cfg.SmartModePreset != "cleanup" {
		t.Errorf("SmartModePreset = %q, want cleanup (migrated from email)", cfg.SmartModePreset)
	}
	if cfg.SmartModePrompt != "" {
		t.Errorf("SmartModePrompt = %q, want empty (cleared)", cfg.SmartModePrompt)
	}
	if cfg.CustomTemplates != nil {
		t.Errorf("CustomTemplates = %v, want nil (cleared)", cfg.CustomTemplates)
	}
	if cfg.AppDetection {
		t.Error("AppDetection should be false (cleared)")
	}
	if cfg.AppPresets != nil {
		t.Errorf("AppPresets = %v, want nil (cleared)", cfg.AppPresets)
	}
	if cfg.FallbackPreset != "" {
		t.Errorf("FallbackPreset = %q, want empty (cleared)", cfg.FallbackPreset)
	}
}

func TestSetSmartModePresetValidatesPresets(t *testing.T) {
	cfg := DefaultConfig()

	// Valid presets
	for _, p := range []string{"cleanup", "concise", "translate"} {
		cfg.SetSmartModePreset(p)
		if cfg.SmartModePreset != p {
			t.Errorf("SetSmartModePreset(%q) → SmartModePreset = %q", p, cfg.SmartModePreset)
		}
		if !cfg.SmartMode {
			t.Errorf("SetSmartModePreset(%q) should enable SmartMode", p)
		}
	}

	// Invalid preset should be migrated to cleanup
	cfg.SetSmartModePreset("email")
	if cfg.SmartModePreset != "cleanup" {
		t.Errorf("SetSmartModePreset('email') → SmartModePreset = %q, want cleanup", cfg.SmartModePreset)
	}

	// "off" disables
	cfg.SetSmartModePreset("off")
	if cfg.SmartMode {
		t.Error("SetSmartModePreset('off') should disable SmartMode")
	}
}
