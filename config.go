package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/whispaste/whispaste/internal/models"
)

// Config holds all application settings.
type Config struct {
	APIKey                  string                   `json:"api_key"`
	APIEndpoint             string                   `json:"api_endpoint"`
	HotkeyMods              []string                 `json:"hotkey_modifiers"`
	HotkeyKey               string                   `json:"hotkey_key"`
	Mode                    string                   `json:"mode"`
	Language                string                   `json:"language"`
	Model                   string                   `json:"model"`
	Prompt                  string                   `json:"prompt"`
	OverlayPos              string                   `json:"overlay_position"`
	AutoPaste               bool                     `json:"auto_paste"`
	PlaySounds              bool                     `json:"play_sounds"`
	CheckUpdates            bool                     `json:"check_updates"`
	UILanguage              string                   `json:"ui_language"`
	Theme                   string                   `json:"theme"`
	Autostart               bool                     `json:"autostart"`
	CloseToTray             bool                     `json:"close_to_tray"`
	SoundVolume             float64                  `json:"sound_volume"`
	MaxRecordSec            int                      `json:"max_record_sec"`
	SmartMode               bool                     `json:"smart_mode"`
	SmartModePreset         string                   `json:"smart_mode_preset"`
	SmartModePrompt         string                   `json:"smart_mode_prompt"`
	SmartModeTarget         string                   `json:"smart_mode_target"`
	SponsorLastRemindedAt   int                      `json:"sponsor_last_reminded_at"`
	NotifyBackground        bool                     `json:"notify_background"`
	NotifyComplete          bool                     `json:"notify_complete"`
	NotifyDonate            bool                     `json:"notify_donate"`
	UseLocalSTT             bool                     `json:"use_local_stt"`
	ActiveModelLocal        bool                     `json:"active_model_local"`
	LocalModelID            string                   `json:"local_model_id"`
	TranscriptionLanguage   string                   `json:"transcription_language"`
	InputDevice             string                   `json:"input_device,omitempty"`
	InputGain               float64                  `json:"input_gain"`
	TagColors               map[string]int           `json:"tag_colors,omitempty"`
	CleanupEnabled          bool                     `json:"cleanup_enabled,omitempty"`
	CleanupMaxEntries       int                      `json:"cleanup_max_entries,omitempty"`
	CleanupMaxAgeDays       int                      `json:"cleanup_max_age_days,omitempty"`
	CleanupIncludePinned    bool                     `json:"cleanup_include_pinned,omitempty"`
	OnboardingDone          bool                     `json:"onboarding_done,omitempty"`
	ActiveProfile           string                   `json:"active_profile,omitempty"`
	Profiles                map[string]ConfigProfile `json:"profiles,omitempty"`
	CustomTemplates         map[string]string        `json:"custom_templates,omitempty"`
	TextReplacementsEnabled bool                     `json:"text_replacements_enabled,omitempty"`
	TextReplacements        []TextReplacement        `json:"text_replacements,omitempty"`
	TextReplacementsAI      bool                     `json:"text_replacements_ai,omitempty"`
	TextReplacementProvider string                   `json:"text_replacement_provider,omitempty"`
	TrimSilence             bool                     `json:"trim_silence,omitempty"`
	AppDetection            bool                     `json:"app_detection,omitempty"`
	AppPresets              map[string]string        `json:"app_presets,omitempty"`
	SmartModeProvider       string                   `json:"smart_mode_provider,omitempty"`
	TemplateMetas           map[string]TemplateMeta  `json:"template_metas,omitempty"`
	FallbackPreset          string                   `json:"fallback_preset,omitempty"`
	CustomTags              []string                 `json:"customTags,omitempty"`
	FloatingButtonEnabled   bool                     `json:"floating_button_enabled,omitempty"`
	FloatingButtonX         int                      `json:"floating_button_x,omitempty"`
	FloatingButtonY         int                      `json:"floating_button_y,omitempty"`
	FloatingButtonColor     string                   `json:"floating_button_color,omitempty"`
	FloatingButtonSize      int                      `json:"floating_button_size,omitempty"`
	FloatingButtonOpacity   int                      `json:"floating_button_opacity,omitempty"`
	FloatingButtonLocked    bool                     `json:"floating_button_locked,omitempty"`
	FloatingButtonBorder    bool                     `json:"floating_button_border,omitempty"`
	UseVAD                  bool                     `json:"use_vad,omitempty"`
	VADSensitivity          float32                  `json:"vad_sensitivity"`
	LastProjectID           string                   `json:"last_project_id,omitempty"`
	SidebarWidth            int                      `json:"sidebar_width,omitempty"`
	DeleteBehavior          string                   `json:"delete_behavior,omitempty"` // "delete" or "archive"
	LocalLLMModel           string                   `json:"local_llm_model,omitempty"`
	UpdateChannel           string                   `json:"update_channel,omitempty"`     // "stable" or "beta"
	CloudSTTProvider        string                   `json:"cloud_stt_provider,omitempty"` // "openai" (default), "groq", "deepgram"
	CloudLLMProvider        string                   `json:"cloud_llm_provider,omitempty"` // "openai" (default), "anthropic", "gemini", "groq"
	CloudLLMModel           string                   `json:"cloud_llm_model,omitempty"`    // provider-specific model ID
	GroqAPIKey              string                   `json:"groq_api_key,omitempty"`
	DeepgramAPIKey          string                   `json:"deepgram_api_key,omitempty"`
	AnthropicAPIKey         string                   `json:"anthropic_api_key,omitempty"`
	GeminiAPIKey            string                   `json:"gemini_api_key,omitempty"`
	CustomDictionary        []string                 `json:"custom_dictionary,omitempty"` // terms for STT/LLM context
	GPUAcceleration         string                   `json:"gpu_acceleration,omitempty"`  // "auto" (default), "enabled", "disabled"
	ErrorReportingEnabled   bool                     `json:"error_reporting_enabled"`
	mu                      sync.RWMutex
}

// TextReplacement defines a trigger→replacement mapping applied to transcriptions.
type TextReplacement struct {
	Trigger     string `json:"trigger"`
	Replacement string `json:"replacement"`
	Enabled     bool   `json:"enabled"`
}

// ConfigProfile stores a named set of transcription & smart mode settings.
type ConfigProfile struct {
	UseLocalSTT           bool   `json:"use_local_stt"`
	ActiveModelLocal      bool   `json:"active_model_local"`
	LocalModelID          string `json:"local_model_id,omitempty"`
	Model                 string `json:"model,omitempty"`
	SmartMode             bool   `json:"smart_mode"`
	SmartModePreset       string `json:"smart_mode_preset,omitempty"`
	SmartModePrompt       string `json:"smart_mode_prompt,omitempty"`
	SmartModeTarget       string `json:"smart_mode_target,omitempty"`
	Language              string `json:"language,omitempty"`
	TranscriptionLanguage string `json:"transcription_language,omitempty"`
}

const defaultSmartModeTargetLanguage = "en"

// DefaultConfig returns a config with sensible defaults.
func DefaultConfig() *Config {
	return &Config{
		HotkeyMods:            []string{"Ctrl", "Shift"},
		HotkeyKey:             "D",
		Mode:                  "push_to_talk",
		Language:              "auto",
		Model:                 "whisper-1",
		OverlayPos:            "top_center",
		AutoPaste:             true,
		PlaySounds:            true,
		CheckUpdates:          true,
		UILanguage:            detectSystemLanguage(),
		Theme:                 "system",
		CloseToTray:           true,
		SoundVolume:           1.0,
		MaxRecordSec:          120,
		NotifyBackground:      true,
		NotifyComplete:        true,
		NotifyDonate:          true,
		SmartModeTarget:       defaultSmartModeTargetLanguage,
		UseLocalSTT:           false,
		LocalModelID:          "whisper-small",
		InputGain:             1.0,
		UpdateChannel:         "stable",
		ErrorReportingEnabled: true,
	}
}

func normalizeSmartTargetLanguage(lang string) string {
	if strings.TrimSpace(lang) == "" {
		return defaultSmartModeTargetLanguage
	}
	return lang
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

// LoadEnvFile loads KEY=VALUE pairs from a .env file in the working
// directory (or the config directory) into os environment variables.
// Existing env vars are NOT overwritten. This keeps secrets out of
// source control while making them available via os.Getenv().
func LoadEnvFile() {
	candidates := []string{".env"}
	if dir, err := configDir(); err == nil {
		candidates = append(candidates, filepath.Join(dir, ".env"))
	}
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			k, v, ok := strings.Cut(line, "=")
			if !ok {
				continue
			}
			k = strings.TrimSpace(k)
			v = strings.TrimSpace(v)
			v = strings.Trim(v, `"'`)
			if k != "" && os.Getenv(k) == "" {
				os.Setenv(k, v)
			}
		}
		logDebug("Loaded env from %s", path)
	}
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
	// Backward compat: old configs lack active_model_local. If legacy
	// use_local_stt was true, the user was actively using local models.
	if !bytes.Contains(data, []byte(`"active_model_local"`)) && cfg.UseLocalSTT {
		cfg.ActiveModelLocal = true
	}
	// Offline-first: if no API key configured and a local model is downloaded,
	// auto-enable local STT so the app works out of the box.
	if !cfg.UseLocalSTT && cfg.APIKey == "" && len(models.ListDownloaded()) > 0 {
		cfg.UseLocalSTT = true
		cfg.ActiveModelLocal = true
	}
	return cfg, nil
}

// Save writes the config to disk with restrictive permissions.
func (c *Config) Save() error {
	c.mu.RLock()
	defer c.mu.RUnlock()

	path, err := configPath()
	if err != nil {
		return fmt.Errorf("Save: config path: %w", err)
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("Save: marshal: %w", err)
	}
	return os.WriteFile(path, data, 0600)
}

// HasAPIKey returns true if an API key is configured.
func (c *Config) HasAPIKey() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.APIKey != ""
}

// HasAnyCloudKey returns true if any cloud provider API key is configured
// (OpenAI, Groq, Deepgram, Anthropic, or Gemini).
func (c *Config) HasAnyCloudKey() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.APIKey != "" || c.GroqAPIKey != "" || c.DeepgramAPIKey != "" ||
		c.AnthropicAPIKey != "" || c.GeminiAPIKey != ""
}

// TODO: The Get* config field getters below follow a repetitive RLock/RUnlock pattern
// that could be replaced by code generation (e.g. go generate + a template).
// Deferring since 30+ getters would need migration and the current approach is safe.

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

// GetUpdateChannel returns the update channel ("stable" or "beta"). Thread-safe.
func (c *Config) GetUpdateChannel() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	ch := c.UpdateChannel
	if ch != "beta" {
		return "stable"
	}
	return ch
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

// GetFloatingButtonEnabled returns whether the floating record button is shown (thread-safe).
func (c *Config) GetFloatingButtonEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FloatingButtonEnabled
}

// GetFloatingButtonPos returns the saved floating button position (thread-safe).
func (c *Config) GetFloatingButtonPos() (int, int) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FloatingButtonX, c.FloatingButtonY
}

// GetFloatingButtonColor returns the floating button color preset name (thread-safe).
// Returns "cyan" as default if not set.
func (c *Config) GetFloatingButtonColor() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.FloatingButtonColor == "" {
		return "cyan"
	}
	return c.FloatingButtonColor
}

// GetFloatingButtonSize returns the floating button diameter in pixels (thread-safe).
// Returns 56 as default. Clamped to [36, 80].
func (c *Config) GetFloatingButtonSize() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	s := c.FloatingButtonSize
	if s <= 0 {
		return 56
	}
	if s < 36 {
		return 36
	}
	if s > 80 {
		return 80
	}
	return s
}

// GetFloatingButtonOpacity returns the idle opacity percentage (30–100, default 70).
func (c *Config) GetFloatingButtonOpacity() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	o := c.FloatingButtonOpacity
	if o <= 0 {
		return 70
	}
	if o < 30 {
		return 30
	}
	if o > 100 {
		return 100
	}
	return o
}

// GetFloatingButtonLocked returns whether the floating button position is locked.
func (c *Config) GetFloatingButtonLocked() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FloatingButtonLocked
}

// GetFloatingButtonBorder returns whether the floating button shows an accent border.
func (c *Config) GetFloatingButtonBorder() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FloatingButtonBorder
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

// GetMode returns the recording mode (thread-safe).
func (c *Config) GetMode() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Mode
}

// GetLanguage returns the configured language preference (thread-safe).
func (c *Config) GetLanguage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Language
}

// GetModel returns the selected cloud STT model (thread-safe).
func (c *Config) GetModel() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Model
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
	return normalizeSmartTargetLanguage(c.SmartModeTarget)
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

// HasAnyModel returns whether at least one transcription model is available:
// either the selected cloud STT provider is configured or a local model is downloaded.
func (c *Config) HasAnyModel() bool {
	if c.HasCloudSTTKey() {
		return true
	}
	return len(models.ListDownloaded()) > 0
}

// HasCloudSTTKey returns true if the selected cloud STT provider has an API key configured.
func (c *Config) HasCloudSTTKey() bool {
	return c.CloudSTTAPIKey() != ""
}

// GetActiveModelLocal returns whether the currently selected model is local (thread-safe).
func (c *Config) GetActiveModelLocal() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.ActiveModelLocal
}

// GetLocalModelID returns the local model ID (thread-safe).
func (c *Config) GetLocalModelID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.LocalModelID == "" {
		return "whisper-base"
	}
	// Migrate removed turbo model to small
	if c.LocalModelID == "whisper-turbo" {
		return "whisper-small"
	}
	return c.LocalModelID
}

// GetLocalLLMModel returns the selected local LLM model ID (thread-safe).
func (c *Config) GetLocalLLMModel() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.LocalLLMModel == "" {
		return "smollm2"
	}
	// Migrate legacy model ID
	if c.LocalLLMModel == "qwen3-0.6b" {
		return "qwen3.5-0.8b"
	}
	return c.LocalLLMModel
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

// GetEffectiveLocalTranscriptionLanguage returns the language hint that local
// STT should actually use. When the configured hint is "auto", local models
// fall back to the UI language because small local whisper models handle auto
// detection poorly.
func (c *Config) GetEffectiveLocalTranscriptionLanguage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	lang := c.TranscriptionLanguage
	if lang == "" {
		lang = c.Language
	}
	if lang == "auto" && c.UILanguage != "" && c.UILanguage != "auto" {
		return c.UILanguage
	}
	return lang
}

// GetLocalTranscriptionMetadataLanguage returns the language metadata that
// should be persisted for local STT results. Unlike the effective local hint,
// this does not turn "auto" into the UI language because that would claim a
// concrete detected language the app does not actually know.
func (c *Config) GetLocalTranscriptionMetadataLanguage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	lang := c.TranscriptionLanguage
	if lang == "" {
		lang = c.Language
	}
	if lang == "auto" {
		return ""
	}
	return lang
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
// An empty string or "off" disables smart mode; any other value enables it with that preset.
func (c *Config) SetSmartModePreset(preset string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if preset == "" || preset == "off" {
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

// GetCleanupIncludePinned returns whether pinned entries are included in cleanup (thread-safe).
func (c *Config) GetCleanupIncludePinned() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CleanupIncludePinned
}

func (c *Config) GetOnboardingDone() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.OnboardingDone
}

// GetActiveProfile returns the active profile name (thread-safe).
func (c *Config) GetActiveProfile() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.ActiveProfile
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
		ActiveModelLocal:      c.ActiveModelLocal,
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
	c.ActiveModelLocal = p.ActiveModelLocal
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

// SaveCustomTemplate stores a user-defined smart mode template.
func (c *Config) SaveCustomTemplate(name, prompt string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.CustomTemplates == nil {
		c.CustomTemplates = make(map[string]string)
	}
	c.CustomTemplates[name] = prompt
}

// DeleteCustomTemplate removes a user-defined template.
func (c *Config) DeleteCustomTemplate(name string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.CustomTemplates, name)
}

// GetCustomTemplates returns all user-defined templates as a copy.
func (c *Config) GetCustomTemplates() map[string]string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make(map[string]string, len(c.CustomTemplates))
	for k, v := range c.CustomTemplates {
		result[k] = v
	}
	return result
}

// GetTextReplacementsEnabled returns whether text replacements are active (thread-safe).
func (c *Config) GetTextReplacementsEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.TextReplacementsEnabled
}

// GetTextReplacementsAI returns whether AI-assisted text replacement matching is enabled (thread-safe).
func (c *Config) GetTextReplacementsAI() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.TextReplacementsAI
}

// GetTextReplacementProvider returns the AI text replacement provider ("local" or "cloud"), defaulting to "local".
func (c *Config) GetTextReplacementProvider() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.TextReplacementProvider == "" {
		return "local"
	}
	return c.TextReplacementProvider
}

// GetTrimSilence returns whether silence trimming is enabled (thread-safe).
func (c *Config) GetTrimSilence() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.TrimSilence
}

// GetUseVAD returns whether Voice Activity Detection is enabled (thread-safe).
func (c *Config) GetUseVAD() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.UseVAD
}

// GetVADSensitivity returns the VAD sensitivity (0.0–1.0, default 0.5) (thread-safe).
func (c *Config) GetVADSensitivity() float32 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.VADSensitivity <= 0 {
		return 0.5
	}
	return c.VADSensitivity
}

// GetAppDetectionEnabled returns whether app-based preset detection is on.
func (c *Config) GetAppDetectionEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.AppDetection
}

// GetAppPresets returns a copy of app→preset mappings (thread-safe).
func (c *Config) GetAppPresets() map[string]string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make(map[string]string, len(c.AppPresets))
	for k, v := range c.AppPresets {
		result[k] = v
	}
	return result
}

// GetSmartModeProvider returns the smart mode provider preference (thread-safe).
func (c *Config) GetSmartModeProvider() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.SmartModeProvider == "" {
		return "auto"
	}
	return c.SmartModeProvider
}

// GetFallbackPreset returns the fallback preset for app detection (thread-safe).
func (c *Config) GetFallbackPreset() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.FallbackPreset == "" {
		return "cleanup"
	}
	return c.FallbackPreset
}

// GetTemplateMetas returns a deep copy of template metadata (thread-safe).
func (c *Config) GetTemplateMetas() map[string]TemplateMeta {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make(map[string]TemplateMeta, len(c.TemplateMetas))
	for k, v := range c.TemplateMetas {
		kw := make([]string, len(v.Keywords))
		copy(kw, v.Keywords)
		result[k] = TemplateMeta{Description: v.Description, Keywords: kw}
	}
	return result
}

// GetCustomTags returns a copy of custom tags (thread-safe).
func (c *Config) GetCustomTags() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make([]string, len(c.CustomTags))
	copy(result, c.CustomTags)
	return result
}

// SetCustomTags replaces the custom tags list (thread-safe).
func (c *Config) SetCustomTags(tags []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.CustomTags = tags
}

// GetLastProjectID returns the last selected project ID (thread-safe).
func (c *Config) GetLastProjectID() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.LastProjectID
}

// SetLastProjectID sets the last selected project ID (thread-safe).
func (c *Config) SetLastProjectID(id string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.LastProjectID = id
}

// GetSidebarWidth returns the sidebar width (thread-safe).
func (c *Config) GetSidebarWidth() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SidebarWidth
}

// SetSidebarWidth sets the sidebar width (thread-safe), clamped to [140, 360].
func (c *Config) SetSidebarWidth(w int) {
	if w < 140 {
		w = 140
	} else if w > 360 {
		w = 360
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.SidebarWidth = w
}

// GetDeleteBehavior returns the delete behavior setting (thread-safe).
// Returns "delete" as default if not set.
func (c *Config) GetDeleteBehavior() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.DeleteBehavior == "" {
		return "delete"
	}
	return c.DeleteBehavior
}

// SetAppPresets replaces the app→preset mappings (thread-safe).
func (c *Config) SetAppPresets(m map[string]string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.AppPresets = m
}

// SetTextReplacementsEnabled sets the text replacements toggle (thread-safe).
func (c *Config) SetTextReplacementsEnabled(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.TextReplacementsEnabled = v
}

// SetTextReplacementsAI sets the AI-assisted text replacement toggle (thread-safe).
func (c *Config) SetTextReplacementsAI(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.TextReplacementsAI = v
}

// SetTextReplacementProvider sets the provider for AI text replacement ("local" or "cloud").
func (c *Config) SetTextReplacementProvider(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.TextReplacementProvider = v
}

// GetTextReplacements returns a copy of all text replacements (thread-safe).
func (c *Config) GetTextReplacements() []TextReplacement {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make([]TextReplacement, len(c.TextReplacements))
	copy(result, c.TextReplacements)
	return result
}

// SetTextReplacements replaces the full list (thread-safe).
func (c *Config) SetTextReplacements(items []TextReplacement) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.TextReplacements = items
}

// ApplyTextReplacements runs all enabled replacements on the given text.
func (c *Config) ApplyTextReplacements(text string) string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if !c.TextReplacementsEnabled {
		return text
	}
	for _, r := range c.TextReplacements {
		if !r.Enabled || r.Trigger == "" {
			continue
		}
		text = strings.ReplaceAll(text, r.Trigger, r.Replacement)
	}
	return text
}

// GetCloudSTTProvider returns the selected cloud STT provider (default: "openai").
func (c *Config) GetCloudSTTProvider() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.CloudSTTProvider == "" {
		return "openai"
	}
	return c.CloudSTTProvider
}

// GetCloudLLMProvider returns the selected cloud LLM provider (default: "openai").
func (c *Config) GetCloudLLMProvider() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.CloudLLMProvider == "" {
		return "openai"
	}
	return c.CloudLLMProvider
}

// GetCloudLLMModel returns the selected cloud LLM model (default: provider-specific).
func (c *Config) GetCloudLLMModel() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.CloudLLMModel
}

// GetGroqAPIKey returns the Groq API key.
func (c *Config) GetGroqAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.GroqAPIKey
}

// GetDeepgramAPIKey returns the Deepgram API key.
func (c *Config) GetDeepgramAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.DeepgramAPIKey
}

// GetAnthropicAPIKey returns the Anthropic API key.
func (c *Config) GetAnthropicAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.AnthropicAPIKey
}

// GetGeminiAPIKey returns the Google Gemini API key.
func (c *Config) GetGeminiAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.GeminiAPIKey
}

// GetCustomDictionary returns a copy of the custom dictionary terms.
func (c *Config) GetCustomDictionary() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	result := make([]string, len(c.CustomDictionary))
	copy(result, c.CustomDictionary)
	return result
}

// SetCustomDictionary replaces the custom dictionary terms.
func (c *Config) SetCustomDictionary(terms []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.CustomDictionary = terms
}

// GetGPUAcceleration returns the GPU acceleration mode (default: "auto").
func (c *Config) GetGPUAcceleration() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.GPUAcceleration == "" {
		return "auto"
	}
	return c.GPUAcceleration
}

// CloudSTTAPIKey returns the appropriate API key for the selected cloud STT provider.
func (c *Config) CloudSTTAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	switch c.CloudSTTProvider {
	case "groq":
		return c.GroqAPIKey
	case "deepgram":
		return c.DeepgramAPIKey
	default:
		return c.APIKey
	}
}

// CloudLLMAPIKey returns the appropriate API key for the selected cloud LLM provider.
func (c *Config) CloudLLMAPIKey() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	switch c.CloudLLMProvider {
	case "anthropic":
		return c.AnthropicAPIKey
	case "gemini":
		return c.GeminiAPIKey
	case "groq":
		return c.GroqAPIKey
	default:
		return c.APIKey
	}
}

// DictionaryPrompt returns the custom dictionary as a comma-separated string
// suitable for Whisper initial_prompt or LLM system prompt injection.
func (c *Config) DictionaryPrompt() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if len(c.CustomDictionary) == 0 {
		return ""
	}
	return strings.Join(c.CustomDictionary, ", ")
}

// cloudSTTAPIKeyLocked returns the STT API key for the selected provider.
// Caller MUST hold c.mu.RLock().
func cloudSTTAPIKeyLocked(c *Config) string {
	switch c.CloudSTTProvider {
	case "groq":
		return c.GroqAPIKey
	case "deepgram":
		return c.DeepgramAPIKey
	default:
		return c.APIKey
	}
}

// cloudLLMAPIKeyLocked returns the LLM API key for the selected provider.
// Caller MUST hold c.mu.RLock().
func cloudLLMAPIKeyLocked(c *Config) string {
	switch c.CloudLLMProvider {
	case "anthropic":
		return c.AnthropicAPIKey
	case "gemini":
		return c.GeminiAPIKey
	case "groq":
		return c.GroqAPIKey
	default:
		return c.APIKey
	}
}

// GetErrorReportingEnabled returns whether anonymous error reporting is on (thread-safe).
func (c *Config) GetErrorReportingEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.ErrorReportingEnabled
}

// SetErrorReportingEnabled toggles anonymous error reporting (thread-safe).
func (c *Config) SetErrorReportingEnabled(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.ErrorReportingEnabled = v
}
