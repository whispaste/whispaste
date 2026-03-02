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
	ctx       *malgo.AllocatedContext
	device    *malgo.Device
	buf       bytes.Buffer
	mu        sync.Mutex
	level     float32
	levelMu   sync.RWMutex
	recording bool
	closeOnce sync.Once
}

// NewRecorder initializes the audio context.
func NewRecorder() (*Recorder, error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, err
	}
	return &Recorder{ctx: ctx}, nil
}

// Start begins capturing audio from the default microphone.
func (r *Recorder) Start() error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.recording {
		return nil
	}

	r.buf.Reset()

	deviceConfig := malgo.DefaultDeviceConfig(malgo.Capture)
	deviceConfig.Capture.Format = malgo.FormatS16
	deviceConfig.Capture.Channels = 1
	deviceConfig.SampleRate = 16000

	callbacks := malgo.DeviceCallbacks{
		Data: func(_, pInputSamples []byte, framecount uint32) {
			r.mu.Lock()
			if r.recording {
				r.buf.Write(pInputSamples)
			}
			r.mu.Unlock()
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

// Close releases all audio resources. Safe to call multiple times.
func (r *Recorder) Close() {
	r.closeOnce.Do(func() {
		r.mu.Lock()
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

func (r *Recorder) computeLevel(samples []byte) {
	n := len(samples) / 2
	if n == 0 {
		return
	}
	var sum float64
	for i := 0; i+1 < len(samples); i += 2 {
		sample := int16(binary.LittleEndian.Uint16(samples[i : i+2]))
		sum += float64(sample) * float64(sample)
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
