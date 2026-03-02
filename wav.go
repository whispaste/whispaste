package main

import "encoding/binary"

// EncodeWAV wraps raw PCM data in a valid WAV/RIFF container.
func EncodeWAV(pcmData []byte, sampleRate uint32, channels uint16, bitsPerSample uint16) []byte {
	dataSize := uint32(len(pcmData))
	byteRate := sampleRate * uint32(channels) * uint32(bitsPerSample) / 8
	blockAlign := channels * bitsPerSample / 8

	buf := make([]byte, 44+len(pcmData))

	// RIFF header
	copy(buf[0:4], "RIFF")
	binary.LittleEndian.PutUint32(buf[4:8], 36+dataSize)
	copy(buf[8:12], "WAVE")

	// fmt sub-chunk
	copy(buf[12:16], "fmt ")
	binary.LittleEndian.PutUint32(buf[16:20], 16) // PCM chunk size
	binary.LittleEndian.PutUint16(buf[20:22], 1)  // AudioFormat = PCM
	binary.LittleEndian.PutUint16(buf[22:24], channels)
	binary.LittleEndian.PutUint32(buf[24:28], sampleRate)
	binary.LittleEndian.PutUint32(buf[28:32], byteRate)
	binary.LittleEndian.PutUint16(buf[32:34], blockAlign)
	binary.LittleEndian.PutUint16(buf[34:36], bitsPerSample)

	// data sub-chunk
	copy(buf[36:40], "data")
	binary.LittleEndian.PutUint32(buf[40:44], dataSize)
	copy(buf[44:], pcmData)

	return buf
}
