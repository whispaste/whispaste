package main

import (
"github.com/whispaste/whispaste/internal/audiocache"
)

// savePendingEntry creates a pending history entry and caches the audio
// when transcription fails or is cancelled.
func savePendingEntry(h *History, pcm []byte, durationSec float64, lang, modelName string, isLocal bool, reason string) {
if len(pcm) < 9600 {
logDebug("Audio too short for pending entry (%d bytes), skipping", len(pcm))
return
}
pendingID := h.AddPendingEntry(durationSec, lang, modelName, isLocal, T(reason))
if pendingID == "" {
return
}
if err := audiocache.Save(pendingID, pcm); err != nil {
logWarn("Save pending audio: %v", err)
}
logInfo("Created pending entry %s (reason: %s, duration: %.1fs)", pendingID, reason, durationSec)
NotifyHistoryChanged()
}
