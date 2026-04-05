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
	APIKey                        string                   `json:"api_key"`
	APIEndpoint                   string                   `json:"api_endpoint"`
	HotkeyMods                    []string                 `json:"hotkey_modifiers"`
	HotkeyKey                     string                   `json:"hotkey_key"`
	Mode                          string                   `json:"mode"`
	Language                      string                   `json:"language"`
	Model                         string                   `json:"model"`
	Prompt                        string                   `json:"prompt"`
	OverlayPos                    string                   `json:"overlay_position"`
	AutoPaste                     bool                     `json:"auto_paste"`
	PlaySounds                    bool                     `json:"play_sounds"`
	CheckUpdates                  bool                     `json:"check_updates"`
	UILanguage                    string                   `json:"ui_language"`
	Theme                         string                   `json:"theme"`
	Autostart                     bool                     `json:"autostart"`
	CloseToTray                   bool                     `json:"close_to_tray"`
	SoundVolume                   float64                  `json:"sound_volume"`
	MaxRecordSec                  int                      `json:"max_record_sec"`
	SmartMode                     bool                     `json:"smart_mode"`
	SmartModePreset               string                   `json:"smart_mode_preset"`
	SmartModePrompt               string                   `json:"smart_mode_prompt"`
	SmartModeTarget               string                   `json:"smart_mode_target"`
	SponsorLastRemindedAt         int                      `json:"sponsor_last_reminded_at"`
	NotifyBackground              bool                     `json:"notify_background"`
	NotifyComplete                bool                     `json:"notify_complete"`
	NotifyDonate                  bool                     `json:"notify_donate"`
	UseLocalSTT                   bool                     `json:"use_local_stt"`
	ActiveModelLocal              bool                     `json:"active_model_local"`
	LocalModelID                  string                   `json:"local_model_id"`
	TranscriptionLanguage         string                   `json:"transcription_language"`
	InputDevice                   string                   `json:"input_device,omitempty"`
	InputGain                     float64                  `json:"input_gain"`
	TagColors                     map[string]int           `json:"tag_colors,omitempty"`
	CleanupEnabled                bool                     `json:"cleanup_enabled,omitempty"`
	CleanupMaxEntries             int                      `json:"cleanup_max_entries,omitempty"`
	CleanupMaxAgeDays             int                      `json:"cleanup_max_age_days,omitempty"`
	CleanupIncludePinned          bool                     `json:"cleanup_include_pinned,omitempty"`
	OnboardingDone                bool                     `json:"onboarding_done,omitempty"`
	ActiveProfile                 string                   `json:"active_profile,omitempty"`
	Profiles                      map[string]ConfigProfile `json:"profiles,omitempty"`
	CustomTemplates               map[string]string        `json:"custom_templates,omitempty"`
	TextReplacementsEnabled       bool                     `json:"text_replacements_enabled,omitempty"`
	TextReplacements              []TextReplacement        `json:"text_replacements,omitempty"`
	TextReplacementsAI            bool                     `json:"text_replacements_ai,omitempty"`
	TextReplacementProvider       string                   `json:"text_replacement_provider,omitempty"`
	TrimSilence                   bool                     `json:"trim_silence,omitempty"`
	AppDetection                  bool                     `json:"app_detection,omitempty"`
	AppPresets                    map[string]string        `json:"app_presets,omitempty"`
	SmartModeProvider             string                   `json:"smart_mode_provider,omitempty"`
	TemplateMetas                 map[string]TemplateMeta  `json:"template_metas,omitempty"`
	FallbackPreset                string                   `json:"fallback_preset,omitempty"`
	CustomTags                    []string                 `json:"customTags,omitempty"`
	FloatingButtonEnabled         bool                     `json:"floating_button_enabled,omitempty"`
	FloatingButtonX               int                      `json:"floating_button_x,omitempty"`
	FloatingButtonY               int                      `json:"floating_button_y,omitempty"`
	FloatingButtonColor           string                   `json:"floating_button_color,omitempty"`
	FloatingButtonCustomColor     string                   `json:"floating_button_custom_color,omitempty"`
	FloatingButtonSize            int                      `json:"floating_button_size,omitempty"`
	FloatingButtonOpacity         int                      `json:"floating_button_opacity,omitempty"`
	FloatingButtonLocked          bool                     `json:"floating_button_locked,omitempty"`
	FloatingButtonBorder          bool                     `json:"floating_button_border,omitempty"`
	FloatingButtonShape           string                   `json:"floating_button_shape,omitempty"`        // "circle", "rounded", "squircle", "hexagon", "diamond", "star"
	FloatingButtonContent         string                   `json:"floating_button_content,omitempty"`      // "microphone", "applogo", "waveform", "custom"
	FloatingButtonCustomImage     string                   `json:"floating_button_custom_image,omitempty"` // absolute path to user-selected PNG/JPG
	FloatingButtonAutoHide        string                   `json:"floating_button_auto_hide,omitempty"`    // "never", "edge", "timeout"
	FloatingButtonAutoHideTimeout int                      `json:"floating_button_auto_hide_timeout,omitempty"`
	UseVAD                        bool                     `json:"use_vad,omitempty"`
	VADSensitivity                float32                  `json:"vad_sensitivity"`
	LastProjectID                 string                   `json:"last_project_id,omitempty"`
	SidebarWidth                  int                      `json:"sidebar_width,omitempty"`
	DeleteBehavior                string                   `json:"delete_behavior,omitempty"` // "delete" or "archive"
	LocalLLMModel                 string                   `json:"local_llm_model,omitempty"`
	CloudSTTProvider              string                   `json:"cloud_stt_provider,omitempty"` // "openai" (default), "groq", "deepgram"
	CloudLLMProvider              string                   `json:"cloud_llm_provider,omitempty"` // "openai" (default), "anthropic", "gemini", "groq"
	CloudLLMModel                 string                   `json:"cloud_llm_model,omitempty"`    // provider-specific model ID
	GroqAPIKey                    string                   `json:"groq_api_key,omitempty"`
	DeepgramAPIKey                string                   `json:"deepgram_api_key,omitempty"`
	AnthropicAPIKey               string                   `json:"anthropic_api_key,omitempty"`
	GeminiAPIKey                  string                   `json:"gemini_api_key,omitempty"`
	CustomDictionary              []string                 `json:"custom_dictionary,omitempty"` // terms for STT/LLM context
	GPUAcceleration               string                   `json:"gpu_acceleration,omitempty"`  // "auto" (default), "enabled", "disabled"
	ErrorReportingEnabled         bool                     `json:"error_reporting_enabled"`
	FeedbackPromptShown           bool                     `json:"feedback_prompt_shown,omitempty"`
	AutoPasteDelay                int                      `json:"auto_paste_delay"` // milliseconds, 0-2000
	AutoTagEnabled                *bool                    `json:"auto_tag_enabled,omitempty"`
	AutoTitleEnabled              *bool                    `json:"auto_title_enabled,omitempty"`
	mu                            sync.RWMutex
}

// TextReplacement defines a trigger→replacement mapping applied to transcriptions.
type TextReplacement struct {
	Trigger     string `json:"trigger"`
	Replacement string `json:"replacement"`
	Enabled     bool   `json:"enabled"`
}

// ConfigProfile stores a named set of transcription & text refinement settings.
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
	// Normalize InputGain to valid range (matches Recorder.SetGain clamp).
	if cfg.InputGain < 0.1 || cfg.InputGain > 3.0 {
		cfg.InputGain = 1.0
	}
	// Migration: removed presets → fallback to "cleanup"
	validPresets := map[string]bool{"cleanup": true, "concise": true, "translate": true, "": true, "off": true}
	if !validPresets[cfg.SmartModePreset] {
		cfg.SmartModePreset = "cleanup"
	}
	// Migration: clear deprecated fields
	cfg.CustomTemplates = nil
	cfg.AppDetection = false
	cfg.AppPresets = nil
	cfg.TemplateMetas = nil
	cfg.FallbackPreset = ""
	cfg.SmartModePrompt = ""
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
// Returns 56 as default. Clamped to [36, 120].
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
	if s > 120 {
		return 120
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

// GetFloatingButtonShape returns the floating button shape (thread-safe).
// Defaults to "circle". Valid values: "circle", "rounded", "squircle".
func (c *Config) GetFloatingButtonShape() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.FloatingButtonShape == "" {
		return "circle"
	}
	return c.FloatingButtonShape
}

// SetFloatingButtonShape sets the floating button shape (thread-safe).
func (c *Config) SetFloatingButtonShape(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch v {
	case "circle", "rounded", "squircle", "hexagon", "diamond", "star":
		c.FloatingButtonShape = v
	default:
		c.FloatingButtonShape = "circle"
	}
}

// GetFloatingButtonCustomColor returns the custom hex color (thread-safe).
// Returns "#22D3EE" (cyan) as default if not set.
func (c *Config) GetFloatingButtonCustomColor() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.FloatingButtonCustomColor == "" {
		return "#22D3EE"
	}
	return c.FloatingButtonCustomColor
}

// SetFloatingButtonCustomColor sets the custom hex color (thread-safe).
func (c *Config) SetFloatingButtonCustomColor(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.FloatingButtonCustomColor = v
}

// GetFloatingButtonContent returns the button icon content type (thread-safe).
// Defaults to "microphone". Valid: "microphone", "applogo", "waveform".
func (c *Config) GetFloatingButtonContent() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	switch c.FloatingButtonContent {
	case "microphone", "applogo", "waveform", "custom":
		return c.FloatingButtonContent
	default:
		return "microphone"
	}
}

// SetFloatingButtonContent sets the button icon content type (thread-safe).
func (c *Config) SetFloatingButtonContent(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch v {
	case "microphone", "applogo", "waveform", "custom":
		c.FloatingButtonContent = v
	default:
		c.FloatingButtonContent = "microphone"
	}
}

// GetFloatingButtonCustomImage returns the path to the user-selected button image (thread-safe).
func (c *Config) GetFloatingButtonCustomImage() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FloatingButtonCustomImage
}

// SetFloatingButtonCustomImage sets the path to the user-selected button image (thread-safe).
func (c *Config) SetFloatingButtonCustomImage(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.FloatingButtonCustomImage = v
}

// GetFloatingButtonAnimation returns "none" (idle animations have been removed).
func (c *Config) GetFloatingButtonAnimation() string {
	return "none"
}

// SetFloatingButtonAnimation is a no-op (idle animations have been removed).
func (c *Config) SetFloatingButtonAnimation(_ string) {}

// GetFloatingButtonSound returns "none" (button sounds have been removed).
func (c *Config) GetFloatingButtonSound() string {
	return "none"
}

// SetFloatingButtonSound is a no-op (button sounds have been removed).
func (c *Config) SetFloatingButtonSound(_ string) {}

// GetFloatingButtonAutoHide returns the auto-hide behavior (thread-safe).
// Defaults to "never". Valid: "never", "edge", "timeout".
func (c *Config) GetFloatingButtonAutoHide() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	switch c.FloatingButtonAutoHide {
	case "never", "edge", "timeout":
		return c.FloatingButtonAutoHide
	default:
		return "never"
	}
}

// SetFloatingButtonAutoHide sets the auto-hide behavior (thread-safe).
func (c *Config) SetFloatingButtonAutoHide(v string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch v {
	case "never", "edge", "timeout":
		c.FloatingButtonAutoHide = v
	default:
		c.FloatingButtonAutoHide = "never"
	}
}

// GetFloatingButtonAutoHideTimeout returns the auto-hide timeout in seconds (thread-safe).
// Defaults to 10. Clamped to [3, 60].
func (c *Config) GetFloatingButtonAutoHideTimeout() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	t := c.FloatingButtonAutoHideTimeout
	if t <= 0 {
		return 10
	}
	if t < 3 {
		return 3
	}
	if t > 60 {
		return 60
	}
	return t
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

// GetAutoPaste returns whether auto-paste is enabled (thread-safe).
func (c *Config) GetAutoPaste() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.AutoPaste
}

// SetAutoPaste sets the auto-paste flag (thread-safe).
func (c *Config) SetAutoPaste(v bool) {
	c.mu.Lock()
	c.AutoPaste = v
	c.mu.Unlock()
}

// GetAutoPasteDelay returns the auto-paste delay in milliseconds (thread-safe).
func (c *Config) GetAutoPasteDelay() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.AutoPasteDelay
}

// SetAutoPasteDelay sets the auto-paste delay in milliseconds, clamped to 0-2000 (thread-safe).
func (c *Config) SetAutoPasteDelay(v int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if v < 0 {
		v = 0
	}
	if v > 2000 {
		v = 2000
	}
	c.AutoPasteDelay = v
}

// GetSmartMode returns whether text refinement is enabled (thread-safe).
func (c *Config) GetSmartMode() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartMode
}

// GetSmartModePreset returns the text refinement preset (thread-safe).
func (c *Config) GetSmartModePreset() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartModePreset
}

// GetSmartModePrompt returns the custom text refinement prompt (thread-safe).
func (c *Config) GetSmartModePrompt() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SmartModePrompt
}

// GetSmartModeTarget returns the text refinement target language (thread-safe).
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
	return supportedLocalLLMModelID
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

// GetSoundVolume returns the sound volume level (thread-safe).
func (c *Config) GetSoundVolume() float64 {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.SoundVolume
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

// SetSmartModePreset sets the text refinement preset and enables/disables text refinement (thread-safe).
// An empty string or "off" disables text refinement; any other value enables it with that preset.
func (c *Config) SetSmartModePreset(preset string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if preset == "" || preset == "off" {
		c.SmartMode = false
	} else {
		validPresets := map[string]bool{"cleanup": true, "concise": true, "translate": true}
		if !validPresets[preset] {
			preset = "cleanup"
		}
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

// GetSmartModeProvider returns the text refinement provider preference (thread-safe).
func (c *Config) GetSmartModeProvider() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.SmartModeProvider == "" {
		return "auto"
	}
	return c.SmartModeProvider
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

// GetFeedbackPromptShown returns whether the feedback prompt has been shown (thread-safe).
func (c *Config) GetFeedbackPromptShown() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.FeedbackPromptShown
}

// SetFeedbackPromptShown sets whether the feedback prompt has been shown (thread-safe).
func (c *Config) SetFeedbackPromptShown(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.FeedbackPromptShown = v
}

// GetAutoTagEnabled returns whether auto-tagging is enabled (thread-safe). Defaults to true.
func (c *Config) GetAutoTagEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.AutoTagEnabled == nil {
		return true
	}
	return *c.AutoTagEnabled
}

// SetAutoTagEnabled sets whether auto-tagging is enabled (thread-safe).
func (c *Config) SetAutoTagEnabled(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.AutoTagEnabled = &v
}

// GetAutoTitleEnabled returns whether auto-title generation is enabled (thread-safe). Defaults to true.
func (c *Config) GetAutoTitleEnabled() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.AutoTitleEnabled == nil {
		return true
	}
	return *c.AutoTitleEnabled
}

// SetAutoTitleEnabled sets whether auto-title generation is enabled (thread-safe).
func (c *Config) SetAutoTitleEnabled(v bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.AutoTitleEnabled = &v
}
