package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"math"
	"strings"
	"sync"

	"github.com/gen2brain/malgo"
)

// applyGain scales 16-bit PCM samples in place by the given gain factor,
// clamping to the int16 range.
func applyGain(samples []byte, gain float64) {
	if gain == 1.0 {
		return
	}
	for i := 0; i+1 < len(samples); i += 2 {
		s := float64(int16(binary.LittleEndian.Uint16(samples[i:i+2]))) * gain
		if s > 32767 {
			s = 32767
		} else if s < -32768 {
			s = -32768
		}
		binary.LittleEndian.PutUint16(samples[i:i+2], uint16(int16(s)))
	}
}

// Recorder captures microphone audio via miniaudio.
type Recorder struct {
	ctx           *malgo.AllocatedContext
	device        *malgo.Device
	buf           bytes.Buffer
	mu            sync.Mutex
	inputDeviceID string
	level         float32
	levelPeak     float32
	levelSum      float64
	levelReads    uint32
	levelMu       sync.RWMutex
	recording     bool
	paused        bool
	monitoring    bool // level-only monitoring (no buffer accumulation)
	monDevice     *malgo.Device
	gain          float64
	closeOnce     sync.Once
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

// SetInputDevice stores the selected capture device ID for future recordings.
func (r *Recorder) SetInputDevice(deviceID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.inputDeviceID = strings.TrimSpace(deviceID)
}

// Start begins capturing audio from the configured microphone.
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
	r.resetLevelState()

	deviceConfig := malgo.DefaultDeviceConfig(malgo.Capture)
	deviceConfig.Capture.Format = malgo.FormatS16
	deviceConfig.Capture.Channels = 1
	deviceConfig.SampleRate = 16000
	deviceName, err := r.configureCaptureDevice(strings.TrimSpace(r.inputDeviceID), &deviceConfig)
	if err != nil {
		return fmt.Errorf("Start: %w", err)
	}

	callbacks := malgo.DeviceCallbacks{
		Data: func(_, pInputSamples []byte, framecount uint32) {
			r.mu.Lock()
			active := r.recording && !r.paused
			g := r.gain
			r.mu.Unlock()
			applyGain(pInputSamples, g)
			r.computeLevel(pInputSamples)
			if o := globalOverlay.Load(); o != nil {
				o.SetAudioLevel(r.GetLevel())
			}
			if active {
				r.mu.Lock()
				r.buf.Write(pInputSamples)
				r.mu.Unlock()
			}
		},
	}

	device, err := malgo.InitDevice(r.ctx.Context, deviceConfig, callbacks)
	if err != nil {
		return fmt.Errorf("Start: init device: %w", err)
	}

	if err := device.Start(); err != nil {
		device.Uninit()
		return fmt.Errorf("Start: start device: %w", err)
	}

	r.device = device
	r.recording = true
	if deviceName != "" {
		logInfo("Recorder started with input device: %s", deviceName)
	}
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
	r.resetLevelState()

	return data, nil
}

// GetLevel returns the current RMS audio level (0.0–1.0).
func (r *Recorder) GetLevel() float32 {
	r.levelMu.RLock()
	defer r.levelMu.RUnlock()
	return r.level
}

type AudioMonitorSnapshot struct {
	Level   float32 `json:"level"`
	Peak    float32 `json:"peak"`
	Average float32 `json:"average"`
	Status  string  `json:"status"`
}

func (r *Recorder) GetMonitorSnapshot() AudioMonitorSnapshot {
	r.levelMu.RLock()
	defer r.levelMu.RUnlock()

	average := float32(0)
	if r.levelReads > 0 {
		average = float32(r.levelSum / float64(r.levelReads))
	}

	return AudioMonitorSnapshot{
		Level:   r.level,
		Peak:    r.levelPeak,
		Average: average,
		Status:  classifyAudioInputHealth(r.levelPeak, average, r.levelReads),
	}
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

	r.resetLevelState()
	deviceConfig := malgo.DefaultDeviceConfig(malgo.Capture)
	deviceConfig.Capture.Format = malgo.FormatS16
	deviceConfig.Capture.Channels = 1
	deviceConfig.SampleRate = 16000
	deviceName, err := r.configureCaptureDevice(strings.TrimSpace(r.inputDeviceID), &deviceConfig)
	if err != nil {
		return fmt.Errorf("StartMonitor: %w", err)
	}

	callbacks := malgo.DeviceCallbacks{
		Data: func(_, pInputSamples []byte, framecount uint32) {
			r.mu.Lock()
			g := r.gain
			r.mu.Unlock()
			applyGain(pInputSamples, g)
			r.computeLevel(pInputSamples)
		},
	}

	device, err := malgo.InitDevice(r.ctx.Context, deviceConfig, callbacks)
	if err != nil {
		return fmt.Errorf("StartMonitor: init device: %w", err)
	}

	if err := device.Start(); err != nil {
		device.Uninit()
		return fmt.Errorf("StartMonitor: start device: %w", err)
	}

	r.monDevice = device
	r.monitoring = true
	if deviceName != "" {
		logInfo("Recorder monitor started with input device: %s", deviceName)
	}
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
	r.resetLevelState()
}

// Close releases all audio resources. Safe to call multiple times.
func (r *Recorder) Close() {
	r.closeOnce.Do(func() {
		// Copy device references under lock, then stop outside lock
		var monDevice, device *malgo.Device
		func() {
			r.mu.Lock()
			defer r.mu.Unlock()
			if r.monitoring && r.monDevice != nil {
				r.monitoring = false
				monDevice = r.monDevice
				r.monDevice = nil
			}
			if r.recording && r.device != nil {
				r.recording = false
				device = r.device
				r.device = nil
			}
		}()

		if monDevice != nil {
			monDevice.Stop()
			monDevice.Uninit()
		}
		if device != nil {
			device.Stop()
			device.Uninit()
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
	if level > r.levelPeak {
		r.levelPeak = level
	}
	r.levelSum += float64(level)
	r.levelReads++
	r.levelMu.Unlock()
}

func (r *Recorder) resetLevelState() {
	r.levelMu.Lock()
	r.level = 0
	r.levelPeak = 0
	r.levelSum = 0
	r.levelReads = 0
	r.levelMu.Unlock()
}

func (r *Recorder) configureCaptureDevice(selectedID string, deviceConfig *malgo.DeviceConfig) (string, error) {
	if selectedID == "" {
		return "", nil
	}

	devices, err := r.ctx.Context.Devices(malgo.Capture)
	if err != nil {
		return "", fmt.Errorf("list capture devices: %w", err)
	}

	for _, info := range devices {
		if info.ID.String() != selectedID {
			continue
		}
		deviceID := info.ID
		deviceConfig.Capture.DeviceID = deviceID.Pointer()
		return info.Name(), nil
	}

	return "", fmt.Errorf("%s", T("audio.device_unavailable"))
}

func classifyAudioInputHealth(peak, average float32, reads uint32) string {
	if reads < 6 {
		return "checking"
	}
	if peak < 0.02 && average < 0.005 {
		return "silent"
	}
	if peak > 0.92 || average > 0.55 {
		return "hot"
	}
	if peak < 0.06 && average < 0.02 {
		return "quiet"
	}
	return "good"
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
			// Keep 250ms margin before voice (industry best practice: 200-300ms)
			margin := sampleRate * 250 / 1000 * 2
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
			// Keep 350ms margin after voice (industry best practice: 300-500ms)
			margin := sampleRate * 350 / 1000 * 2
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
