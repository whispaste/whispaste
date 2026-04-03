//go:build windows

package main

import (
	_ "embed"
	"encoding/binary"
	"math"
	"runtime"
	"sync/atomic"
	"time"
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
	sndAsync     = 0x00000001
	sndMemory    = 0x00000004
	sndNoDefault = 0x00000002
)

// soundVolumeBits stores the playback volume as atomic uint64 (float64 bits).
var soundVolumeBits uint64 = math.Float64bits(1.0)

// soundChan serializes all sound playback to avoid PlaySoundW cancellation issues.
// PlaySoundW can only play one sound at a time; concurrent calls cancel the previous.
var soundChan = make(chan []byte, 16)

func init() {
	go func() {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		for data := range soundChan {
			ret, _, _ := procPlaySound.Call(
				uintptr(unsafe.Pointer(&data[0])),
				0,
				uintptr(sndMemory|sndNoDefault|sndAsync),
			)
			if ret == 0 {
				logWarn("PlaySoundW failed for queued sound (%d bytes)", len(data))
			} else {
				logDebug("PlaySoundW OK (%d bytes)", len(data))
			}
			time.Sleep(100 * time.Millisecond)
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
	case SoundButtonClick:
		data = sndBtnClick
	case SoundButtonPop:
		data = sndBtnPop
	case SoundButtonChime:
		data = sndBtnChime
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
		logWarn("Sound queue full, dropping %v sound", soundType)
	}
}

var sndWarning []byte
var sndBtnClick []byte
var sndBtnPop []byte
var sndBtnChime []byte

func init() {
	sndWarning = generateBeepWAV(880, 200, 0.5)
	sndBtnClick = generateClickWAV()
	sndBtnPop = generatePopWAV()
	sndBtnChime = generateChimeWAV()
}

// generateClickWAV creates a short percussive click sound.
func generateClickWAV() []byte {
	sampleRate := 16000
	durationMs := 30
	numSamples := sampleRate * durationMs / 1000
	dataSize := numSamples * 2
	wav := makeWAVHeader(dataSize, sampleRate)
	for i := 0; i < numSamples; i++ {
		t := float64(i) / float64(sampleRate)
		decay := math.Exp(-t * 200)
		sample := int16(0.6 * 32767 * decay * math.Sin(2*math.Pi*2500*t))
		binary.LittleEndian.PutUint16(wav[44+i*2:44+i*2+2], uint16(sample))
	}
	return wav
}

// generatePopWAV creates a bubbly pop sound with pitch sweep.
func generatePopWAV() []byte {
	sampleRate := 16000
	durationMs := 80
	numSamples := sampleRate * durationMs / 1000
	dataSize := numSamples * 2
	wav := makeWAVHeader(dataSize, sampleRate)
	for i := 0; i < numSamples; i++ {
		t := float64(i) / float64(sampleRate)
		decay := math.Exp(-t * 40)
		freq := 600 + 800*math.Exp(-t*30)
		sample := int16(0.5 * 32767 * decay * math.Sin(2*math.Pi*freq*t))
		binary.LittleEndian.PutUint16(wav[44+i*2:44+i*2+2], uint16(sample))
	}
	return wav
}

// generateChimeWAV creates a pleasant two-tone chime.
func generateChimeWAV() []byte {
	sampleRate := 16000
	durationMs := 200
	numSamples := sampleRate * durationMs / 1000
	dataSize := numSamples * 2
	wav := makeWAVHeader(dataSize, sampleRate)
	for i := 0; i < numSamples; i++ {
		t := float64(i) / float64(sampleRate)
		decay1 := math.Exp(-t * 10)
		decay2 := math.Exp(-(t - 0.08) * 10)
		if t < 0.08 {
			decay2 = 0
		}
		s := 0.4*decay1*math.Sin(2*math.Pi*1047*t) + 0.3*decay2*math.Sin(2*math.Pi*1319*t)
		sample := int16(s * 32767)
		binary.LittleEndian.PutUint16(wav[44+i*2:44+i*2+2], uint16(sample))
	}
	return wav
}

// makeWAVHeader creates a standard 44-byte WAV header for mono 16-bit PCM.
func makeWAVHeader(dataSize, sampleRate int) []byte {
	wav := make([]byte, 44+dataSize)
	copy(wav[0:4], "RIFF")
	binary.LittleEndian.PutUint32(wav[4:8], uint32(36+dataSize))
	copy(wav[8:12], "WAVE")
	copy(wav[12:16], "fmt ")
	binary.LittleEndian.PutUint32(wav[16:20], 16)
	binary.LittleEndian.PutUint16(wav[20:22], 1)
	binary.LittleEndian.PutUint16(wav[22:24], 1)
	binary.LittleEndian.PutUint32(wav[24:28], uint32(sampleRate))
	binary.LittleEndian.PutUint32(wav[28:32], uint32(sampleRate*2))
	binary.LittleEndian.PutUint16(wav[32:34], 2)
	binary.LittleEndian.PutUint16(wav[34:36], 16)
	copy(wav[36:40], "data")
	binary.LittleEndian.PutUint32(wav[40:44], uint32(dataSize))
	return wav
}

// generateBeepWAV creates a sine wave PCM WAV in memory.
func generateBeepWAV(freqHz, durationMs int, amplitude float64) []byte {
	sampleRate := 16000
	numSamples := sampleRate * durationMs / 1000
	dataSize := numSamples * 2
	wav := makeWAVHeader(dataSize, sampleRate)
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
