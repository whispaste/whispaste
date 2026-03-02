package main

// AppState represents the current state of the application.
type AppState int

const (
	StateIdle         AppState = iota
	StateRecording
	StateTranscribing
)

// SoundType identifies audio feedback sounds.
type SoundType int

const (
	SoundRecordStart SoundType = iota
	SoundRecordStop
	SoundSuccess
	SoundError
)

// OverlayUpdate carries state and audio level data to the overlay window.
type OverlayUpdate struct {
	State      AppState
	AudioLevel float32 // 0.0–1.0 for waveform
	Elapsed    float64 // seconds since recording started
	Text       string  // status text or error message
}

const (
	AppName    = "Whispaste"
	AppVersion = "1.0.0"
)
