package main

import (
	"encoding/binary"
	"testing"
)

func TestEncodeWAVHeader(t *testing.T) {
	pcm := make([]byte, 100)
	wav := EncodeWAV(pcm, 16000, 1, 16)

	if len(wav) != 44+100 {
		t.Fatalf("WAV length = %d, want %d", len(wav), 144)
	}

	// RIFF header
	if string(wav[0:4]) != "RIFF" {
		t.Error("Missing RIFF tag")
	}
	riffSize := binary.LittleEndian.Uint32(wav[4:8])
	if riffSize != uint32(36+100) {
		t.Errorf("RIFF size = %d, want %d", riffSize, 136)
	}
	if string(wav[8:12]) != "WAVE" {
		t.Error("Missing WAVE tag")
	}

	// fmt sub-chunk
	if string(wav[12:16]) != "fmt " {
		t.Error("Missing fmt tag")
	}
	fmtSize := binary.LittleEndian.Uint32(wav[16:20])
	if fmtSize != 16 {
		t.Errorf("fmt size = %d, want 16", fmtSize)
	}
	audioFormat := binary.LittleEndian.Uint16(wav[20:22])
	if audioFormat != 1 {
		t.Errorf("AudioFormat = %d, want 1 (PCM)", audioFormat)
	}
	channels := binary.LittleEndian.Uint16(wav[22:24])
	if channels != 1 {
		t.Errorf("Channels = %d, want 1", channels)
	}
	sampleRate := binary.LittleEndian.Uint32(wav[24:28])
	if sampleRate != 16000 {
		t.Errorf("SampleRate = %d, want 16000", sampleRate)
	}
	byteRate := binary.LittleEndian.Uint32(wav[28:32])
	if byteRate != 32000 {
		t.Errorf("ByteRate = %d, want 32000", byteRate)
	}
	blockAlign := binary.LittleEndian.Uint16(wav[32:34])
	if blockAlign != 2 {
		t.Errorf("BlockAlign = %d, want 2", blockAlign)
	}
	bitsPerSample := binary.LittleEndian.Uint16(wav[34:36])
	if bitsPerSample != 16 {
		t.Errorf("BitsPerSample = %d, want 16", bitsPerSample)
	}

	// data sub-chunk
	if string(wav[36:40]) != "data" {
		t.Error("Missing data tag")
	}
	dataSize := binary.LittleEndian.Uint32(wav[40:44])
	if dataSize != 100 {
		t.Errorf("Data size = %d, want 100", dataSize)
	}
}

func TestEncodeWAVEmptyPCM(t *testing.T) {
	wav := EncodeWAV(nil, 16000, 1, 16)
	if len(wav) != 44 {
		t.Errorf("Empty WAV length = %d, want 44 (header only)", len(wav))
	}
	dataSize := binary.LittleEndian.Uint32(wav[40:44])
	if dataSize != 0 {
		t.Errorf("Empty WAV data size = %d, want 0", dataSize)
	}
}

func TestEncodeWAVStereo(t *testing.T) {
	pcm := make([]byte, 200)
	wav := EncodeWAV(pcm, 44100, 2, 16)

	channels := binary.LittleEndian.Uint16(wav[22:24])
	if channels != 2 {
		t.Errorf("Channels = %d, want 2", channels)
	}
	sampleRate := binary.LittleEndian.Uint32(wav[24:28])
	if sampleRate != 44100 {
		t.Errorf("SampleRate = %d, want 44100", sampleRate)
	}
	byteRate := binary.LittleEndian.Uint32(wav[28:32])
	// 44100 * 2 * 16/8 = 176400
	if byteRate != 176400 {
		t.Errorf("ByteRate = %d, want 176400", byteRate)
	}
	blockAlign := binary.LittleEndian.Uint16(wav[32:34])
	if blockAlign != 4 {
		t.Errorf("BlockAlign = %d, want 4", blockAlign)
	}
}

func TestEncodeWAVDataIntegrity(t *testing.T) {
	pcm := []byte{0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE}
	wav := EncodeWAV(pcm, 16000, 1, 16)

	for i, b := range pcm {
		if wav[44+i] != b {
			t.Errorf("PCM byte %d: got %02x, want %02x", i, wav[44+i], b)
		}
	}
}
