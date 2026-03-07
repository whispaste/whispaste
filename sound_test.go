package main

import (
	"encoding/binary"
	"math"
	"testing"
)

func TestSetSoundVolume(t *testing.T) {
	tests := []struct {
		name string
		set  float64
		want float64
	}{
		{"normal", 0.5, 0.5},
		{"max", 1.0, 1.0},
		{"min", 0.0, 0.0},
		{"above max clamped", 2.0, 1.0},
		{"below min clamped", -0.5, 0.0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			SetSoundVolume(tt.set)
			got := getSoundVolume()
			if got != tt.want {
				t.Errorf("after SetSoundVolume(%f), getSoundVolume() = %f, want %f", tt.set, got, tt.want)
			}
		})
	}
}

func TestGenerateBeepWAV(t *testing.T) {
	wav := generateBeepWAV(440, 100, 0.5)

	// Check RIFF header
	if string(wav[:4]) != "RIFF" {
		t.Error("missing RIFF header")
	}
	if string(wav[8:12]) != "WAVE" {
		t.Error("missing WAVE format")
	}

	// Check fmt chunk
	if string(wav[12:16]) != "fmt " {
		t.Error("missing fmt chunk")
	}
	audioFormat := binary.LittleEndian.Uint16(wav[20:22])
	if audioFormat != 1 {
		t.Errorf("audio format = %d, want 1 (PCM)", audioFormat)
	}
	channels := binary.LittleEndian.Uint16(wav[22:24])
	if channels != 1 {
		t.Errorf("channels = %d, want 1 (mono)", channels)
	}
	sampleRate := binary.LittleEndian.Uint32(wav[24:28])
	if sampleRate != 16000 {
		t.Errorf("sample rate = %d, want 16000", sampleRate)
	}

	// Check data chunk
	if string(wav[36:40]) != "data" {
		t.Error("missing data chunk")
	}
	expectedSamples := 16000 * 100 / 1000 // 1600 samples
	expectedDataSize := expectedSamples * 2
	dataSize := binary.LittleEndian.Uint32(wav[40:44])
	if int(dataSize) != expectedDataSize {
		t.Errorf("data size = %d, want %d", dataSize, expectedDataSize)
	}

	// Total size: 44 header + data
	if len(wav) != 44+expectedDataSize {
		t.Errorf("total WAV size = %d, want %d", len(wav), 44+expectedDataSize)
	}
}

func TestScaleWAVVolume(t *testing.T) {
	t.Run("half volume", func(t *testing.T) {
		wav := generateBeepWAV(440, 50, 1.0)
		scaled := scaleWAVVolume(wav, 0.5)

		if len(scaled) != len(wav) {
			t.Fatalf("scaled length %d != original %d", len(scaled), len(wav))
		}
		// Headers should be identical
		if string(scaled[:44]) != string(wav[:44]) {
			t.Error("header should not change")
		}

		// Check that samples are approximately halved
		for i := 44; i+1 < len(wav); i += 2 {
			origSample := int16(binary.LittleEndian.Uint16(wav[i : i+2]))
			scaledSample := int16(binary.LittleEndian.Uint16(scaled[i : i+2]))
			expected := int16(float64(origSample) * 0.5)
			diff := math.Abs(float64(scaledSample - expected))
			if diff > 1 {
				t.Errorf("at offset %d: scaled=%d, expected≈%d (orig=%d)", i, scaledSample, expected, origSample)
				break
			}
		}
	})

	t.Run("zero volume", func(t *testing.T) {
		wav := generateBeepWAV(440, 50, 1.0)
		scaled := scaleWAVVolume(wav, 0.0)

		for i := 44; i+1 < len(scaled); i += 2 {
			sample := int16(binary.LittleEndian.Uint16(scaled[i : i+2]))
			if sample != 0 {
				t.Errorf("at offset %d: sample=%d, want 0 at zero volume", i, sample)
				break
			}
		}
	})

	t.Run("short wav unchanged", func(t *testing.T) {
		short := []byte("too short")
		result := scaleWAVVolume(short, 0.5)
		if string(result) != string(short) {
			t.Error("WAV shorter than 44 bytes should be returned unchanged")
		}
	})
}
