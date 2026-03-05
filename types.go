package main

// AppState represents the current state of the application.
type AppState int

const (
	StateIdle         AppState = iota
	StateRecording
	StateTranscribing
	StateProcessing // AI post-processing via Smart Mode
	StateError
	StateCopied
	StatePaused // recording is paused
)

// SoundType identifies audio feedback sounds.
type SoundType int

const (
	SoundRecordStart SoundType = iota
	SoundRecordStop
	SoundSuccess
	SoundError
	SoundWarning
)

const AppName = "WhisPaste"

// AppVersion is set via -ldflags "-X main.AppVersion=x.y.z" at build time.
var AppVersion = "0.1.1-alpha"

// BuildCommit is the git commit hash, injected via -ldflags at build time.
var BuildCommit = ""

// BuildDate is the build timestamp, injected via -ldflags at build time.
var BuildDate = ""

// TemplateMeta holds metadata for a smart mode template (builtin or custom).
type TemplateMeta struct {
	Description string   `json:"description"`
	Keywords    []string `json:"keywords"`
}

// debugMode enables WebView2 DevTools and verbose logging.
// Set via WHISPASTE_DEBUG=1 environment variable.
var debugMode bool
