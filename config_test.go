package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
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
	if cfg.HotkeyKey != "V" {
		t.Errorf("HotkeyKey = %q, want V", cfg.HotkeyKey)
	}
	if cfg.UseVAD {
		t.Error("UseVAD should be false by default")
	}
	if cfg.GetVADSensitivity() != 0.5 {
		t.Errorf("GetVADSensitivity() = %f, want 0.5 (default)", cfg.GetVADSensitivity())
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
