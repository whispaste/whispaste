package main

import (
	_ "embed"
	"unsafe"

	"golang.org/x/sys/windows"
)

//go:embed resources/snd_start.wav
var sndStart []byte

//go:embed resources/snd_stop.wav
var sndStop []byte

//go:embed resources/snd_success.wav
var sndSuccess []byte

//go:embed resources/snd_error.wav
var sndError []byte

var (
	winmm        = windows.NewLazySystemDLL("winmm.dll")
	procPlaySound = winmm.NewProc("PlaySoundW")
)

const (
	sndMemory    = 0x00000004
	sndAsync     = 0x00000001
	sndNoDefault = 0x00000002
)

// PlayFeedback plays an audio cue. Uses SND_ASYNC for non-blocking playback.
// Note: Windows only allows one async sound at a time — calling this again
// cancels the previous sound. For overlapping sounds, wrap in a goroutine.
func PlayFeedback(soundType SoundType) {
	var data []byte
	switch soundType {
	case SoundRecordStart:
		data = sndStart
	case SoundRecordStop:
		data = sndStop
	case SoundSuccess:
		data = sndSuccess
	case SoundError:
		data = sndError
	default:
		return
	}
	if len(data) == 0 {
		return
	}
	// Play in a goroutine with SND_SYNC to avoid cancellation of previous sounds.
	// Each goroutine gets its own reference to the data slice (embedded, never GC'd).
	go func(d []byte) {
		defer func() { recover() }()
		procPlaySound.Call(
			uintptr(unsafe.Pointer(&d[0])),
			0,
			uintptr(sndMemory|sndNoDefault), // SND_SYNC (no sndAsync flag)
		)
	}(data)
}
