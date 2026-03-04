package main

import (
	_ "embed"
	"encoding/binary"
	"math"
	"runtime"
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
	winmm         = windows.NewLazySystemDLL("winmm.dll")
	procPlaySound = winmm.NewProc("PlaySoundW")
)

const (
	sndMemory    = 0x00000004
	sndNoDefault = 0x00000002
)

// soundVolumeBits stores the playback volume as atomic uint64 (float64 bits).
var soundVolumeBits uint64 = math.Float64bits(1.0)

// soundChan serializes all sound playback to avoid PlaySoundW cancellation issues.
// PlaySoundW can only play one sound at a time; concurrent calls cancel the previous.
var soundChan = make(chan []byte, 8)

func init() {
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		for data := range soundChan {
			procPlaySound.Call(
				uintptr(unsafe.Pointer(&data[0])),
				0,
				uintptr(sndMemory|sndNoDefault),
			)
			runtime.KeepAlive(data)
		}
	}()
}

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
	case SoundWarning:
		data = sndWarning
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

	// Send to serialized playback goroutine; drop if channel full
	select {
	case soundChan <- playData:
	default:
	}
}

var sndWarning []byte

func init() {
	sndWarning = generateBeepWAV(880, 200, 0.5)
}

// generateBeepWAV creates a sine wave PCM WAV in memory.
func generateBeepWAV(freqHz, durationMs int, amplitude float64) []byte {
	sampleRate := 16000
	numSamples := sampleRate * durationMs / 1000
	dataSize := numSamples * 2 // 16-bit mono
	wav := make([]byte, 44+dataSize)
	copy(wav[0:4], "RIFF")
	binary.LittleEndian.PutUint32(wav[4:8], uint32(36+dataSize))
	copy(wav[8:12], "WAVE")
	copy(wav[12:16], "fmt ")
	binary.LittleEndian.PutUint32(wav[16:20], 16)
	binary.LittleEndian.PutUint16(wav[20:22], 1) // PCM
	binary.LittleEndian.PutUint16(wav[22:24], 1) // mono
	binary.LittleEndian.PutUint32(wav[24:28], uint32(sampleRate))
	binary.LittleEndian.PutUint32(wav[28:32], uint32(sampleRate*2))
	binary.LittleEndian.PutUint16(wav[32:34], 2)  // block align
	binary.LittleEndian.PutUint16(wav[34:36], 16) // bits per sample
	copy(wav[36:40], "data")
	binary.LittleEndian.PutUint32(wav[40:44], uint32(dataSize))
	for i := 0; i < numSamples; i++ {
		t := float64(i) / float64(sampleRate)
		sample := int16(amplitude * 32767 * math.Sin(2*math.Pi*float64(freqHz)*t))
		binary.LittleEndian.PutUint16(wav[44+i*2:44+i*2+2], uint16(sample))
	}
	return wav
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
