package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

// Config holds all application settings.
type Config struct {
	APIKey      string   `json:"api_key"`
	APIEndpoint string   `json:"api_endpoint"`
	HotkeyMods  []string `json:"hotkey_modifiers"`
	HotkeyKey   string   `json:"hotkey_key"`
	Mode        string   `json:"mode"`
	Language    string   `json:"language"`
	Model       string   `json:"model"`
	Prompt      string   `json:"prompt"`
	OverlayPos  string   `json:"overlay_position"`
	AutoPaste    bool     `json:"auto_paste"`
	PlaySounds   bool     `json:"play_sounds"`
	CheckUpdates bool     `json:"check_updates"`
	UILanguage   string   `json:"ui_language"`
	Theme        string   `json:"theme"`
	Autostart    bool     `json:"autostart"`
	SoundVolume  float64  `json:"sound_volume"`
	MaxRecordSec int      `json:"max_record_sec"`
	SmartMode       bool   `json:"smart_mode"`
	SmartModePreset string `json:"smart_mode_preset"`
	SmartModePrompt string `json:"smart_mode_prompt"`
	SmartModeTarget string `json:"smart_mode_target"`
	SponsorShown    bool   `json:"sponsor_shown"`
	UseLocalSTT     bool   `json:"use_local_stt"`
	LocalModelID    string `json:"local_model_id"`
	mu          sync.RWMutex
}

// DefaultConfig returns a config with sensible defaults.
func DefaultConfig() *Config {
	return &Config{
		HotkeyMods:   []string{"Ctrl", "Shift"},
		HotkeyKey:    "V",
		Mode:         "push_to_talk",
		Language:     "auto",
		Model:        "whisper-1",
		OverlayPos:   "top_center",
		AutoPaste:    true,
		PlaySounds:   true,
		CheckUpdates: true,
		UILanguage:   detectSystemLanguage(),
		Theme:        "system",
		SoundVolume:  1.0,
		MaxRecordSec: 120,
		UseLocalSTT:  false,
		LocalModelID: "whisper-tiny",
	}
}

// configDir returns the path to %APPDATA%\Whispaste.
func configDir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, AppName)
	return dir, os.MkdirAll(dir, 0700)
}

// configPath returns the full path to the config file.
func configPath() (string, error) {
	dir, err := configDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "config.json"), nil
}

// LoadConfig reads config from disk, or returns defaults if not found.
func LoadConfig() (*Config, error) {
	path, err := configPath()
	if err != nil {
		return DefaultConfig(), err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultConfig(), nil
		}
		return DefaultConfig(), err
	}
	cfg := DefaultConfig()
	if err := json.Unmarshal(data, cfg); err != nil {
		return DefaultConfig(), fmt.Errorf("invalid config: %w", err)
	}
	return cfg, nil
}

// Save writes the config to disk with restrictive permissions.
func (c *Config) Save() error {
	c.mu.RLock()
	defer c.mu.RUnlock()

	path, err := configPath()
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}

// HasAPIKey returns true if an API key is configured.
func (c *Config) HasAPIKey() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.APIKey != ""
}

// GetAPIKey returns the API key (thread-safe).
func (c *Config) GetAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.APIKey
}

// GetUILanguage returns the UI language (thread-safe).
func (c *Config) GetUILanguage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.UILanguage
}

// GetTheme returns the current theme setting (thread-safe).
func (c *Config) GetTheme() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Theme
}

// SetAPIKey sets the API key (thread-safe).
func (c *Config) SetAPIKey(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.APIKey = key
}

// GetCheckUpdates returns whether auto-update checks are enabled (thread-safe).
func (c *Config) GetCheckUpdates() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CheckUpdates
}

// GetOverlayPos returns the overlay position preference (thread-safe).
func (c *Config) GetOverlayPos() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.OverlayPos
}

// IsPushToTalk returns true if the mode is push-to-talk.
func (c *Config) IsPushToTalk() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Mode == "push_to_talk"
}

// detectSystemLanguage returns "de" for German systems, "en" otherwise.
func detectSystemLanguage() string {
	// Check common environment variables
	for _, key := range []string{"LANG", "LANGUAGE", "LC_ALL", "LC_MESSAGES"} {
		if val := os.Getenv(key); val != "" {
			if len(val) >= 2 && (val[:2] == "de") {
				return "de"
			}
		}
	}
	// On Windows, we'll detect via GetUserDefaultUILanguage in the main init
	return "en"
}

// GetAPIEndpoint returns the API endpoint URL (thread-safe).
func (c *Config) GetAPIEndpoint() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.APIEndpoint != "" {
		return c.APIEndpoint
	}
	return "https://api.openai.com/v1/audio/transcriptions"
}

// GetPrompt returns the Whisper prompt (thread-safe).
func (c *Config) GetPrompt() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Prompt
}

// GetMaxRecordSec returns the max recording duration (thread-safe).
func (c *Config) GetMaxRecordSec() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.MaxRecordSec < 0 {
		return 120
	}
	return c.MaxRecordSec // 0 = unlimited
}

// GetSmartMode returns whether Smart Mode is enabled (thread-safe).
func (c *Config) GetSmartMode() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartMode
}

// GetSmartModePreset returns the Smart Mode preset (thread-safe).
func (c *Config) GetSmartModePreset() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartModePreset
}

// GetSmartModePrompt returns the custom Smart Mode prompt (thread-safe).
func (c *Config) GetSmartModePrompt() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartModePrompt
}

// GetSmartModeTarget returns the Smart Mode target language (thread-safe).
func (c *Config) GetSmartModeTarget() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartModeTarget
}

// GetSponsorShown returns whether the sponsor balloon has been shown (thread-safe).
func (c *Config) GetSponsorShown() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SponsorShown
}

// SetSponsorShown sets whether the sponsor balloon has been shown (thread-safe).
func (c *Config) SetSponsorShown(v bool) {
	c.mu.Lock()
	c.SponsorShown = v
	c.mu.Unlock()
}

// GetUseLocalSTT returns whether local STT is enabled (thread-safe).
func (c *Config) GetUseLocalSTT() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.UseLocalSTT
}

// GetLocalModelID returns the local model ID (thread-safe).
func (c *Config) GetLocalModelID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.LocalModelID == "" {
		return "whisper-tiny"
	}
	return c.LocalModelID
}

// SetSmartModePreset sets the smart mode preset and enables/disables smart mode (thread-safe).
func (c *Config) SetSmartModePreset(preset string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if preset == "off" {
		c.SmartMode = false
	} else {
		c.SmartMode = true
		c.SmartModePreset = preset
	}
}
