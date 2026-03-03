package main

import (
	_ "embed"
	"encoding/binary"
	"math"
	"sync/atomic"
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

// soundVolumeBits stores the playback volume as atomic uint64 (float64 bits).
var soundVolumeBits uint64 = math.Float64bits(1.0)

// SetSoundVolume updates the playback volume level (0.0–1.0).
func SetSoundVolume(v float64) {
	if v < 0 {
		v = 0
	}
	if v > 1 {
		v = 1
	}
	atomic.StoreUint64(&soundVolumeBits, math.Float64bits(v))
}

func getSoundVolume() float64 {
	return math.Float64frombits(atomic.LoadUint64(&soundVolumeBits))
}

// PlayFeedback plays an audio cue scaled by the current volume level.
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

	vol := getSoundVolume()
	if vol <= 0 {
		return
	}

	playData := data
	if vol < 1.0 {
		playData = scaleWAVVolume(data, vol)
	}

	// Play in a goroutine with SND_SYNC to avoid cancellation of previous sounds.
	go func(d []byte) {
		defer func() { recover() }()
		procPlaySound.Call(
			uintptr(unsafe.Pointer(&d[0])),
			0,
			uintptr(sndMemory|sndNoDefault), // SND_SYNC
		)
	}(playData)
}

// scaleWAVVolume scales 16-bit PCM samples in a WAV byte slice by a volume factor.
func scaleWAVVolume(wav []byte, vol float64) []byte {
	if len(wav) < 44 {
		return wav
	}
	out := make([]byte, len(wav))
	copy(out, wav)

	// WAV header is 44 bytes for standard PCM; data starts after header
	dataOffset := 44
	for i := dataOffset; i+1 < len(out); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(out[i : i+2]))
		scaled := int32(float64(sample) * vol)
		if scaled > 32767 {
			scaled = 32767
		}
		if scaled < -32768 {
			scaled = -32768
		}
		binary.LittleEndian.PutUint16(out[i:i+2], uint16(int16(scaled)))
	}
	return out
}
