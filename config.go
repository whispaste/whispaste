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
	HotkeyMods  []string `json:"hotkey_modifiers"`
	HotkeyKey   string   `json:"hotkey_key"`
	Mode        string   `json:"mode"`
	Language    string   `json:"language"`
	Model       string   `json:"model"`
	OverlayPos  string   `json:"overlay_position"`
	AutoPaste    bool     `json:"auto_paste"`
	PlaySounds   bool     `json:"play_sounds"`
	CheckUpdates bool     `json:"check_updates"`
	UILanguage   string   `json:"ui_language"`
	Theme        string   `json:"theme"`
	Autostart    bool     `json:"autostart"`
	mu          sync.RWMutex
}

// DefaultConfig returns a config with sensible defaults.
func DefaultConfig() *Config {
	return &Config{
		HotkeyMods:  []string{"Ctrl", "Shift"},
		HotkeyKey:   "V",
		Mode:        "push_to_talk",
		Language:    "auto",
		Model:       "whisper-1",
		OverlayPos:  "top_center",
		AutoPaste:    true,
		PlaySounds:   true,
		CheckUpdates: true,
		UILanguage:  detectSystemLanguage(),
		Theme:       "system",
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
