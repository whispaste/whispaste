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
	sndMemory = 0x00000004
	sndAsync  = 0x00000001
	sndNoDefault = 0x00000002
)

// PlayFeedback plays an audio cue asynchronously using embedded WAV data.
// SND_ASYNC makes PlaySoundW non-blocking, so no goroutine needed.
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
	// Recover from panic if winmm.dll is unavailable (Windows N editions)
	defer func() { recover() }()
	procPlaySound.Call(
		uintptr(unsafe.Pointer(&data[0])),
		0,
		uintptr(sndMemory|sndAsync|sndNoDefault),
	)
}
