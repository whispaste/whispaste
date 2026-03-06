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

// TrimSilence removes leading and trailing silence from 16-bit mono PCM data.
// windowMs sets the analysis window size; threshold is the RMS level (0.0–1.0)
// below which audio is considered silence. A small margin of audio before/after
// the first/last voiced segment is preserved to avoid clipping.
func TrimSilence(data []byte, threshold float32, windowMs int) []byte {
	if len(data) < 2 || threshold <= 0 {
		return data
	}
	const sampleRate = 16000
	samplesPerWindow := sampleRate * windowMs / 1000
	if samplesPerWindow < 1 {
		samplesPerWindow = 1
	}
	bytesPerWindow := samplesPerWindow * 2
	totalSamples := len(data) / 2

	// RMS of a window
	rmsWindow := func(offset, count int) float32 {
		var sum float64
		for i := 0; i < count && offset+i*2+1 < len(data); i++ {
			s := float64(int16(binary.LittleEndian.Uint16(data[offset+i*2 : offset+i*2+2])))
			sum += s * s
		}
		rms := math.Sqrt(sum / float64(count))
		return float32(rms / 32768.0)
	}

	// Find first voiced window from start
	startByte := 0
	for off := 0; off < len(data)-1; off += bytesPerWindow {
		n := samplesPerWindow
		if off/2+n > totalSamples {
			n = totalSamples - off/2
		}
		if rmsWindow(off, n) >= threshold {
			// Keep 50ms margin before voice
			margin := sampleRate * 50 / 1000 * 2
			startByte = off - margin
			if startByte < 0 {
				startByte = 0
			}
			// Align to 2-byte boundary
			startByte = startByte &^ 1
			break
		}
	}

	// Find last voiced window from end
	endByte := len(data)
	for off := (len(data) / bytesPerWindow) * bytesPerWindow; off >= 0; off -= bytesPerWindow {
		if off >= len(data) {
			continue
		}
		n := samplesPerWindow
		if off/2+n > totalSamples {
			n = totalSamples - off/2
		}
		if n > 0 && rmsWindow(off, n) >= threshold {
			// Keep 50ms margin after voice
			margin := sampleRate * 50 / 1000 * 2
			endByte = off + bytesPerWindow + margin
			if endByte > len(data) {
				endByte = len(data)
			}
			// Align to 2-byte boundary
			endByte = endByte &^ 1
			break
		}
	}

	if startByte >= endByte {
		return data
	}
	return data[startByte:endByte]
}

// StripInternalSilence removes contiguous silent regions longer than
// minSilenceMs from the middle of PCM audio (16-bit LE, 16 kHz mono).
// A short crossfade (10 ms) is kept at each splice to avoid clicks.
func StripInternalSilence(data []byte, threshold float32, minSilenceMs int) []byte {
	if len(data) < 2 || threshold <= 0 || minSilenceMs <= 0 {
		return data
	}

	const sampleRate = 16000
	const windowMs = 30
	samplesPerWindow := sampleRate * windowMs / 1000
	bytesPerWindow := samplesPerWindow * 2
	minSilenceWindows := (sampleRate * minSilenceMs / 1000) / samplesPerWindow
	if minSilenceWindows < 1 {
		minSilenceWindows = 1
	}

	// crossfade margin in bytes (10 ms on each side)
	crossfadeBytes := sampleRate * 10 / 1000 * 2
	if crossfadeBytes < 2 {
		crossfadeBytes = 2
	}

	rmsWindow := func(offset, count int) float32 {
		var sum float64
		for i := 0; i < count && offset+i*2+1 < len(data); i++ {
			s := float64(int16(binary.LittleEndian.Uint16(data[offset+i*2 : offset+i*2+2])))
			sum += s * s
		}
		return float32(math.Sqrt(sum/float64(count)) / 32768.0)
	}

	totalSamples := len(data) / 2

	// Classify each window as silent or voiced
	type region struct {
		startByte, endByte int
	}
	var silentRegions []region
	silentStart := -1
	silentCount := 0

	for off := 0; off < len(data)-1; off += bytesPerWindow {
		n := samplesPerWindow
		if off/2+n > totalSamples {
			n = totalSamples - off/2
		}
		if n <= 0 {
			break
		}
		if rmsWindow(off, n) < threshold {
			if silentStart < 0 {
				silentStart = off
			}
			silentCount++
		} else {
			if silentCount >= minSilenceWindows {
				silentRegions = append(silentRegions, region{silentStart, off})
			}
			silentStart = -1
			silentCount = 0
		}
	}
	// Don't strip trailing silence (TrimSilence handles that)

	if len(silentRegions) == 0 {
		return data
	}

	// Build output by copying voiced segments, skipping silent regions
	// but keeping crossfade margins at boundaries.
	var out bytes.Buffer
	out.Grow(len(data))
	cursor := 0
	for _, r := range silentRegions {
		// Keep crossfade before the silent region
		keepEnd := r.startByte + crossfadeBytes
		if keepEnd > r.endByte {
			keepEnd = r.endByte
		}
		out.Write(data[cursor:keepEnd])

		// Skip to crossfade before the end of the silent region
		cursor = r.endByte - crossfadeBytes
		if cursor < keepEnd {
			cursor = keepEnd
		}
		// Align to 2-byte boundary
		cursor = cursor &^ 1
	}
	// Write remaining data
	if cursor < len(data) {
		out.Write(data[cursor:])
	}

	result := out.Bytes()
	if len(result) < 2 {
		return data
	}
	return result
}
