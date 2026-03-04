package main

import (
	"bytes"
	"encoding/binary"
	"math"
	"sync"

	"github.com/gen2brain/malgo"
)

// Recorder captures microphone audio via miniaudio.
type Recorder struct {
	ctx        *malgo.AllocatedContext
	device     *malgo.Device
	buf        bytes.Buffer
	mu         sync.Mutex
	level      float32
	levelMu    sync.RWMutex
	recording  bool
	paused     bool
	monitoring bool // level-only monitoring (no buffer accumulation)
	monDevice  *malgo.Device
	gain       float64
	closeOnce  sync.Once
}

// NewRecorder initializes the audio context.
func NewRecorder() (*Recorder, error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, err
	}
	return &Recorder{ctx: ctx, gain: 1.0}, nil
}

// SetGain sets the input gain multiplier (applied to level computation and samples).
func (r *Recorder) SetGain(g float64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if g < 0.1 {
		g = 0.1
	}
	if g > 3.0 {
		g = 3.0
	}
	r.gain = g
}

// Start begins capturing audio from the default microphone.
func (r *Recorder) Start() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.recording {
		return nil
	}

	// Stop monitor if running (avoids dual-capture conflict)
	if r.monitoring {
		r.stopMonitorLocked()
	}

	r.buf.Reset()
	r.paused = false

	deviceConfig := malgo.DefaultDeviceConfig(malgo.Capture)
	deviceConfig.Capture.Format = malgo.FormatS16
	deviceConfig.Capture.Channels = 1
	deviceConfig.SampleRate = 16000

	callbacks := malgo.DeviceCallbacks{
		Data: func(_, pInputSamples []byte, framecount uint32) {
			r.mu.Lock()
			active := r.recording && !r.paused
			g := r.gain
			r.mu.Unlock()
			// Apply gain to samples for both recording and level computation
			if g != 1.0 {
				for i := 0; i+1 < len(pInputSamples); i += 2 {
					s := float64(int16(binary.LittleEndian.Uint16(pInputSamples[i:i+2]))) * g
					if s > 32767 {
						s = 32767
					} else if s < -32768 {
						s = -32768
					}
					binary.LittleEndian.PutUint16(pInputSamples[i:i+2], uint16(int16(s)))
				}
			}
			if active {
				r.mu.Lock()
				r.buf.Write(pInputSamples)
				r.mu.Unlock()
				r.computeLevel(pInputSamples)
			}
		},
	}

	device, err := malgo.InitDevice(r.ctx.Context, deviceConfig, callbacks)
	if err != nil {
		return err
	}

	if err := device.Start(); err != nil {
		device.Uninit()
		return err
	}

	r.device = device
	r.recording = true
	return nil
}

// Stop ends the capture and returns the accumulated PCM data.
func (r *Recorder) Stop() ([]byte, error) {
	r.mu.Lock()
	if !r.recording || r.device == nil {
		r.mu.Unlock()
		return nil, nil
	}
	r.recording = false
	r.paused = false
	device := r.device
	r.device = nil
	r.mu.Unlock()

	// Stop outside lock to avoid deadlock with data callback
	device.Stop()
	device.Uninit()

	r.mu.Lock()
	data := make([]byte, r.buf.Len())
	copy(data, r.buf.Bytes())
	r.buf.Reset()
	r.mu.Unlock()

	return data, nil
}

// GetLevel returns the current RMS audio level (0.0–1.0).
func (r *Recorder) GetLevel() float32 {
	r.levelMu.RLock()
	defer r.levelMu.RUnlock()
	return r.level
}

// Pause temporarily stops accumulating audio data without stopping the device.
func (r *Recorder) Pause() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.recording {
		r.paused = true
	}
}

// Resume continues accumulating audio data after a pause.
func (r *Recorder) Resume() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.recording && r.paused {
		r.paused = false
	}
}

// IsPaused returns whether the recorder is currently paused.
func (r *Recorder) IsPaused() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.paused
}

// StartMonitor starts audio capture for level monitoring only (no buffer accumulation).
// Use this for the settings VU meter. Returns error if already recording or monitoring.
func (r *Recorder) StartMonitor() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.recording || r.monitoring {
		return nil
	}

	deviceConfig := malgo.DefaultDeviceConfig(malgo.Capture)
	deviceConfig.Capture.Format = malgo.FormatS16
	deviceConfig.Capture.Channels = 1
	deviceConfig.SampleRate = 16000

	callbacks := malgo.DeviceCallbacks{
		Data: func(_, pInputSamples []byte, framecount uint32) {
			// Apply gain for accurate level display
			r.mu.Lock()
			g := r.gain
			r.mu.Unlock()
			if g != 1.0 {
				for i := 0; i+1 < len(pInputSamples); i += 2 {
					s := float64(int16(binary.LittleEndian.Uint16(pInputSamples[i:i+2]))) * g
					if s > 32767 {
						s = 32767
					} else if s < -32768 {
						s = -32768
					}
					binary.LittleEndian.PutUint16(pInputSamples[i:i+2], uint16(int16(s)))
				}
			}
			r.computeLevel(pInputSamples)
		},
	}

	device, err := malgo.InitDevice(r.ctx.Context, deviceConfig, callbacks)
	if err != nil {
		return err
	}

	if err := device.Start(); err != nil {
		device.Uninit()
		return err
	}

	r.monDevice = device
	r.monitoring = true
	return nil
}

// StopMonitor stops level-only monitoring.
func (r *Recorder) StopMonitor() {
	r.mu.Lock()
	r.stopMonitorLocked()
	r.mu.Unlock()
}

// stopMonitorLocked stops level-only monitoring. Caller must hold r.mu.
func (r *Recorder) stopMonitorLocked() {
	if !r.monitoring || r.monDevice == nil {
		return
	}
	r.monitoring = false
	device := r.monDevice
	r.monDevice = nil

	// Unlock while stopping device (may block)
	r.mu.Unlock()
	device.Stop()
	device.Uninit()
	r.mu.Lock()

	// Reset level to zero
	r.levelMu.Lock()
	r.level = 0
	r.levelMu.Unlock()
}

// Close releases all audio resources. Safe to call multiple times.
func (r *Recorder) Close() {
	r.closeOnce.Do(func() {
		r.mu.Lock()
		if r.monitoring && r.monDevice != nil {
			r.monitoring = false
			monDevice := r.monDevice
			r.monDevice = nil
			r.mu.Unlock()
			monDevice.Stop()
			monDevice.Uninit()
			r.mu.Lock()
		}
		if r.recording && r.device != nil {
			r.recording = false
			device := r.device
			r.device = nil
			r.mu.Unlock()
			device.Stop()
			device.Uninit()
		} else {
			r.mu.Unlock()
		}

		if r.ctx != nil {
			r.ctx.Uninit()
			r.ctx.Free()
			r.ctx = nil
		}
	})
}

// AudioDeviceInfo represents an audio input device.
type AudioDeviceInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// ListAudioDevices returns available audio capture devices.
func ListAudioDevices() ([]AudioDeviceInfo, error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, err
	}
	defer func() {
		ctx.Uninit()
		ctx.Free()
	}()

	devices, err := ctx.Context.Devices(malgo.Capture)
	if err != nil {
		return nil, err
	}

	var result []AudioDeviceInfo
	for _, d := range devices {
		result = append(result, AudioDeviceInfo{
			ID:   d.ID.String(),
			Name: d.Name(),
		})
	}
	return result, nil
}

func (r *Recorder) computeLevel(samples []byte) {
	n := len(samples) / 2
	if n == 0 {
		return
	}
	var sum float64
	for i := 0; i+1 < len(samples); i += 2 {
		sample := float64(int16(binary.LittleEndian.Uint16(samples[i : i+2])))
		sum += sample * sample
	}
	rms := math.Sqrt(sum / float64(n))
	level := float32(rms / 32768.0)
	if level > 1.0 {
		level = 1.0
	}
	r.levelMu.Lock()
	r.level = level
	r.levelMu.Unlock()
}
