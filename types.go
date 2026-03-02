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

const (
	AppName    = "Whispaste"
	AppVersion = "1.0.0"
)
