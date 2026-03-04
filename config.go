package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
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
	CloseToTray  bool     `json:"close_to_tray"`
	SoundVolume  float64  `json:"sound_volume"`
	MaxRecordSec int      `json:"max_record_sec"`
	SmartMode       bool   `json:"smart_mode"`
	SmartModePreset string `json:"smart_mode_preset"`
	SmartModePrompt string `json:"smart_mode_prompt"`
	SmartModeTarget string `json:"smart_mode_target"`
	SponsorLastRemindedAt int `json:"sponsor_last_reminded_at"`
	NotifyBackground bool  `json:"notify_background"`
	NotifyComplete   bool  `json:"notify_complete"`
	NotifyDonate     bool  `json:"notify_donate"`
	UseLocalSTT            bool   `json:"use_local_stt"`
	LocalModelID           string `json:"local_model_id"`
	TranscriptionLanguage  string `json:"transcription_language"`
	InputDevice     string  `json:"input_device,omitempty"`
	InputGain       float64 `json:"input_gain"`
	TagColors       map[string]int `json:"tag_colors,omitempty"`
	CleanupEnabled    bool `json:"cleanup_enabled,omitempty"`
	CleanupMaxEntries int  `json:"cleanup_max_entries,omitempty"`
	CleanupMaxAgeDays int  `json:"cleanup_max_age_days,omitempty"`
	OnboardingDone    bool `json:"onboarding_done,omitempty"`
	ActiveProfile     string                    `json:"active_profile,omitempty"`
	Profiles          map[string]ConfigProfile   `json:"profiles,omitempty"`
	mu          sync.RWMutex
}

// ConfigProfile stores a named set of transcription & smart mode settings.
type ConfigProfile struct {
	UseLocalSTT     bool   `json:"use_local_stt"`
	LocalModelID    string `json:"local_model_id,omitempty"`
	Model           string `json:"model,omitempty"`
	SmartMode       bool   `json:"smart_mode"`
	SmartModePreset string `json:"smart_mode_preset,omitempty"`
	SmartModePrompt string `json:"smart_mode_prompt,omitempty"`
	SmartModeTarget string `json:"smart_mode_target,omitempty"`
	Language        string `json:"language,omitempty"`
	TranscriptionLanguage string `json:"transcription_language,omitempty"`
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
		CloseToTray: true,
		SoundVolume:  1.0,
		MaxRecordSec: 120,
		NotifyBackground: true,
		NotifyComplete:   true,
		NotifyDonate:     true,
		UseLocalSTT:      false,
		LocalModelID:     "whisper-tiny",
		InputGain:        1.0,
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

// GetCloseToTray returns whether the app minimizes to tray on close (thread-safe).
func (c *Config) GetCloseToTray() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CloseToTray
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

// GetSponsorLastRemindedAt returns the dictation count at which the sponsor balloon was last shown (thread-safe).
func (c *Config) GetSponsorLastRemindedAt() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SponsorLastRemindedAt
}

// SetSponsorLastRemindedAt sets the dictation count at which the sponsor balloon was last shown (thread-safe).
func (c *Config) SetSponsorLastRemindedAt(v int) {
	c.mu.Lock()
	c.SponsorLastRemindedAt = v
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

// GetTranscriptionLanguage returns the local STT language hint (thread-safe).
// Returns the explicit value if set, or falls back to the global Language setting.
func (c *Config) GetTranscriptionLanguage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.TranscriptionLanguage != "" {
		return c.TranscriptionLanguage
	}
	return c.Language
}

// GetInputDevice returns the selected input device ID (thread-safe).
func (c *Config) GetInputDevice() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.InputDevice
}

// GetInputGain returns the input gain multiplier (thread-safe).
func (c *Config) GetInputGain() float64 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.InputGain
}

// GetNotifyBackground returns whether the background notification is enabled (thread-safe).
func (c *Config) GetNotifyBackground() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.NotifyBackground
}

// GetNotifyComplete returns whether the transcription complete notification is enabled (thread-safe).
func (c *Config) GetNotifyComplete() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.NotifyComplete
}

// GetNotifyDonate returns whether the donation reminder notification is enabled (thread-safe).
func (c *Config) GetNotifyDonate() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.NotifyDonate
}

// GetTagColors returns a copy of the tag-to-color-index mapping (thread-safe).
func (c *Config) GetTagColors() map[string]int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.TagColors == nil {
		return map[string]int{}
	}
	m := make(map[string]int, len(c.TagColors))
	for k, v := range c.TagColors {
		m[k] = v
	}
	return m
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

// GetCleanupEnabled returns whether auto-cleanup is enabled (thread-safe).
func (c *Config) GetCleanupEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CleanupEnabled
}

// GetCleanupMaxEntries returns the max number of history entries to keep (thread-safe).
func (c *Config) GetCleanupMaxEntries() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CleanupMaxEntries
}

// GetCleanupMaxAgeDays returns the max age in days for history entries (thread-safe).
func (c *Config) GetCleanupMaxAgeDays() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CleanupMaxAgeDays
}

func (c *Config) GetOnboardingDone() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.OnboardingDone
}

func (c *Config) SetOnboardingDone(done bool) {
	c.mu.Lock()
	c.OnboardingDone = done
	c.mu.Unlock()
}

// SaveProfile saves current transcription settings as a named profile.
func (c *Config) SaveProfile(name string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.Profiles == nil {
		c.Profiles = make(map[string]ConfigProfile)
	}
	c.Profiles[name] = ConfigProfile{
		UseLocalSTT:           c.UseLocalSTT,
		LocalModelID:          c.LocalModelID,
		Model:                 c.Model,
		SmartMode:             c.SmartMode,
		SmartModePreset:       c.SmartModePreset,
		SmartModePrompt:       c.SmartModePrompt,
		SmartModeTarget:       c.SmartModeTarget,
		Language:              c.Language,
		TranscriptionLanguage: c.TranscriptionLanguage,
	}
	c.ActiveProfile = name
}

// LoadProfile applies a named profile's settings to the config.
func (c *Config) LoadProfile(name string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	p, ok := c.Profiles[name]
	if !ok {
		return false
	}
	c.UseLocalSTT = p.UseLocalSTT
	c.LocalModelID = p.LocalModelID
	c.Model = p.Model
	c.SmartMode = p.SmartMode
	c.SmartModePreset = p.SmartModePreset
	c.SmartModePrompt = p.SmartModePrompt
	c.SmartModeTarget = p.SmartModeTarget
	c.Language = p.Language
	c.TranscriptionLanguage = p.TranscriptionLanguage
	c.ActiveProfile = name
	return true
}

// DeleteProfile removes a named profile.
func (c *Config) DeleteProfile(name string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.Profiles, name)
	if c.ActiveProfile == name {
		c.ActiveProfile = ""
	}
}

// ListProfiles returns profile names.
func (c *Config) ListProfiles() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	var names []string
	for name := range c.Profiles {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}
