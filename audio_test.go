package main

import (
	"bytes"
	"encoding/binary"
	"math"
	"testing"
)

func TestApplyGain(t *testing.T) {
	t.Run("gain 1.0 is no-op", func(t *testing.T) {
		orig := generatePCM(0.5, 50)
		data := make([]byte, len(orig))
		copy(data, orig)
		applyGain(data, 1.0)
		if !bytes.Equal(data, orig) {
			t.Error("gain 1.0 should not modify samples")
		}
	})

	t.Run("gain 2.0 doubles amplitude", func(t *testing.T) {
		data := make([]byte, 4)
		neg := int16(-1000)
		binary.LittleEndian.PutUint16(data[0:2], uint16(int16(1000)))
		binary.LittleEndian.PutUint16(data[2:4], uint16(neg))
		applyGain(data, 2.0)
		s0 := int16(binary.LittleEndian.Uint16(data[0:2]))
		s1 := int16(binary.LittleEndian.Uint16(data[2:4]))
		if s0 != 2000 {
			t.Errorf("sample 0: got %d, want 2000", s0)
		}
		if s1 != -2000 {
			t.Errorf("sample 1: got %d, want -2000", s1)
		}
	})

	t.Run("clipping at positive max", func(t *testing.T) {
		data := make([]byte, 2)
		binary.LittleEndian.PutUint16(data, uint16(int16(20000)))
		applyGain(data, 2.0)
		s := int16(binary.LittleEndian.Uint16(data))
		if s != 32767 {
			t.Errorf("positive clip: got %d, want 32767", s)
		}
	})

	t.Run("clipping at negative max", func(t *testing.T) {
		data := make([]byte, 2)
		neg := int16(-20000)
		binary.LittleEndian.PutUint16(data, uint16(neg))
		applyGain(data, 2.0)
		s := int16(binary.LittleEndian.Uint16(data))
		if s != -32768 {
			t.Errorf("negative clip: got %d, want -32768", s)
		}
	})

	t.Run("gain 0.5 halves amplitude", func(t *testing.T) {
		data := make([]byte, 2)
		binary.LittleEndian.PutUint16(data, uint16(int16(1000)))
		applyGain(data, 0.5)
		s := int16(binary.LittleEndian.Uint16(data))
		if s != 500 {
			t.Errorf("half gain: got %d, want 500", s)
		}
	})

	t.Run("empty data is safe", func(t *testing.T) {
		applyGain(nil, 2.0)
		applyGain([]byte{}, 2.0)
	})

	t.Run("odd byte count ignores trailing byte", func(t *testing.T) {
		data := []byte{0xE8, 0x03, 0xFF} // 1000 + trailing byte
		applyGain(data, 2.0)
		s := int16(binary.LittleEndian.Uint16(data[0:2]))
		if s != 2000 {
			t.Errorf("odd-length: got %d, want 2000", s)
		}
		if data[2] != 0xFF {
			t.Error("trailing byte was modified")
		}
	})
}

func TestComputeLevelWithGain(t *testing.T) {
	r := &Recorder{}
	samples := generatePCM(0.10, 50) // quiet sine ~10% amplitude

	// Raw level.
	r.computeLevel(samples)
	rawLevel := r.GetLevel()

	// Apply gain 2.0 to a copy and recompute.
	amplified := make([]byte, len(samples))
	copy(amplified, samples)
	applyGain(amplified, 2.0)
	r.computeLevel(amplified)
	amplifiedLevel := r.GetLevel()

	if amplifiedLevel <= rawLevel {
		t.Errorf("amplified level (%f) should be greater than raw level (%f)", amplifiedLevel, rawLevel)
	}
	// RMS scales linearly with gain; allow 5% tolerance for int16 rounding.
	ratio := float64(amplifiedLevel) / float64(rawLevel)
	if ratio < 1.90 || ratio > 2.10 {
		t.Errorf("expected ~2.0x ratio, got %.3f (raw=%f, amplified=%f)", ratio, rawLevel, amplifiedLevel)
	}
}

func TestComputeLevelWithHighGain(t *testing.T) {
	r := &Recorder{}
	// Loud signal at 80% amplitude + gain 3.0 → heavy clipping.
	loud := generatePCM(0.80, 50)
	applyGain(loud, 3.0)
	r.computeLevel(loud)
	level := r.GetLevel()

	if level < 0.90 {
		t.Errorf("clipped signal level should be near 1.0, got %f", level)
	}
	if level > 1.0 {
		t.Errorf("level must not exceed 1.0, got %f", level)
	}
}

func TestGainDoesNotAffectLevelWhenOne(t *testing.T) {
	r := &Recorder{}
	samples := generatePCM(0.40, 50)

	r.computeLevel(samples)
	before := r.GetLevel()

	// Gain 1.0 is documented as a no-op — level must stay identical.
	applyGain(samples, 1.0)
	r.computeLevel(samples)
	after := r.GetLevel()

	if before != after {
		t.Errorf("gain 1.0 changed level: before=%f, after=%f", before, after)
	}
}

func TestClassifyAudioInputHealth(t *testing.T) {
	tests := []struct {
		name    string
		peak    float32
		average float32
		reads   uint32
		want    string
	}{
		{name: "checking until enough samples", peak: 0.20, average: 0.08, reads: 2, want: "checking"},
		{name: "silent signal", peak: 0.01, average: 0.003, reads: 12, want: "silent"},
		{name: "quiet signal", peak: 0.04, average: 0.015, reads: 12, want: "quiet"},
		{name: "healthy signal", peak: 0.34, average: 0.14, reads: 12, want: "good"},
		{name: "too hot", peak: 0.96, average: 0.40, reads: 12, want: "hot"},
	}

	for _, tt := range tests {
		if got := classifyAudioInputHealth(tt.peak, tt.average, tt.reads); got != tt.want {
			t.Errorf("%s: classifyAudioInputHealth(%0.3f, %0.3f, %d) = %q, want %q", tt.name, tt.peak, tt.average, tt.reads, got, tt.want)
		}
	}
}

// generatePCM creates 16-bit LE PCM data at 16 kHz mono with a given amplitude and duration.
func generatePCM(amplitude float64, durationMs int) []byte {
	sampleRate := 16000
	numSamples := sampleRate * durationMs / 1000
	data := make([]byte, numSamples*2)
	for i := 0; i < numSamples; i++ {
		// Generate a sine wave at 440 Hz
		sample := amplitude * math.Sin(2*math.Pi*440*float64(i)/float64(sampleRate))
		s := int16(sample * 32767)
		binary.LittleEndian.PutUint16(data[i*2:], uint16(s))
	}
	return data
}

// generateSilence creates silent PCM data (all zeros) for a given duration.
func generateSilence(durationMs int) []byte {
	sampleRate := 16000
	numSamples := sampleRate * durationMs / 1000
	return make([]byte, numSamples*2)
}

func TestTrimSilence(t *testing.T) {
	t.Run("empty data returns as-is", func(t *testing.T) {
		got := TrimSilence(nil, 0.01, 30)
		if got != nil {
			t.Errorf("expected nil, got %d bytes", len(got))
		}
	})

	t.Run("all-silence returns original", func(t *testing.T) {
		silence := generateSilence(500)
		got := TrimSilence(silence, 0.01, 30)
		if len(got) != len(silence) {
			t.Errorf("all-silence should return original: got %d, want %d", len(got), len(silence))
		}
	})

	t.Run("trims leading silence", func(t *testing.T) {
		leading := generateSilence(1000)
		speech := generatePCM(0.5, 500)
		pcm := append(leading, speech...)
		got := TrimSilence(pcm, 0.01, 30)
		// Result should be shorter than input (leading silence removed minus margin)
		if len(got) >= len(pcm) {
			t.Errorf("expected trimmed result, got same or larger: %d >= %d", len(got), len(pcm))
		}
		// But should still contain the speech portion
		if len(got) < len(speech) {
			t.Errorf("result too short — speech may be clipped: %d < %d", len(got), len(speech))
		}
	})

	t.Run("trims trailing silence", func(t *testing.T) {
		speech := generatePCM(0.5, 500)
		trailing := generateSilence(1000)
		pcm := append(speech, trailing...)
		got := TrimSilence(pcm, 0.01, 30)
		if len(got) >= len(pcm) {
			t.Errorf("expected trimmed result, got same or larger: %d >= %d", len(got), len(pcm))
		}
		if len(got) < len(speech) {
			t.Errorf("result too short — speech may be clipped: %d < %d", len(got), len(speech))
		}
	})

	t.Run("preserves speech with margins", func(t *testing.T) {
		leading := generateSilence(2000)
		speech := generatePCM(0.5, 300)
		trailing := generateSilence(2000)
		pcm := append(leading, speech...)
		pcm = append(pcm, trailing...)
		got := TrimSilence(pcm, 0.01, 30)
		// Should be significantly shorter than 4300ms total
		if len(got) >= len(pcm)/2 {
			t.Errorf("expected significant trimming: got %d bytes from %d", len(got), len(pcm))
		}
		// 250ms pre + 300ms speech + 350ms post = ~900ms minimum expected
		minExpected := 16000 * 800 / 1000 * 2 // ~800ms worth
		if len(got) < minExpected {
			t.Errorf("result too short (margins may be missing): %d < %d", len(got), minExpected)
		}
	})

	t.Run("zero threshold returns original", func(t *testing.T) {
		pcm := generatePCM(0.1, 500)
		got := TrimSilence(pcm, 0, 30)
		if len(got) != len(pcm) {
			t.Errorf("zero threshold should return original: got %d, want %d", len(got), len(pcm))
		}
	})
}

func TestStripInternalSilence(t *testing.T) {
	t.Run("empty data returns as-is", func(t *testing.T) {
		got := StripInternalSilence(nil, 0.01, 600)
		if got != nil {
			t.Errorf("expected nil, got %d bytes", len(got))
		}
	})

	t.Run("no internal silence preserved", func(t *testing.T) {
		speech := generatePCM(0.5, 2000)
		got := StripInternalSilence(speech, 0.01, 600)
		// Continuous speech should remain roughly the same length
		if len(got) < len(speech)*90/100 {
			t.Errorf("continuous speech should not be stripped: got %d, want ~%d", len(got), len(speech))
		}
	})

	t.Run("strips long internal silence", func(t *testing.T) {
		part1 := generatePCM(0.5, 500)
		gap := generateSilence(2000) // 2s silence (above 600ms threshold)
		part2 := generatePCM(0.5, 500)
		pcm := append(part1, gap...)
		pcm = append(pcm, part2...)
		got := StripInternalSilence(pcm, 0.01, 600)
		// Should be shorter than original (2s gap removed)
		if len(got) >= len(pcm)*80/100 {
			t.Errorf("expected internal silence stripped: got %d from %d", len(got), len(pcm))
		}
	})

	t.Run("preserves short internal pauses", func(t *testing.T) {
		part1 := generatePCM(0.5, 500)
		gap := generateSilence(400) // 400ms (below 600ms threshold)
		part2 := generatePCM(0.5, 500)
		pcm := append(part1, gap...)
		pcm = append(pcm, part2...)
		got := StripInternalSilence(pcm, 0.01, 600)
		// Should preserve the short gap
		if len(got) < len(pcm)*90/100 {
			t.Errorf("short pause should be preserved: got %d from %d", len(got), len(pcm))
		}
	})

	t.Run("zero threshold returns original", func(t *testing.T) {
		pcm := generatePCM(0.1, 500)
		got := StripInternalSilence(pcm, 0, 600)
		if len(got) != len(pcm) {
			t.Errorf("zero threshold should return original: got %d, want %d", len(got), len(pcm))
		}
	})
}
