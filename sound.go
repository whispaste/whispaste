package main

import (
	"time"

	"golang.org/x/sys/windows"
)

var (
	sndKernel32 = windows.NewLazySystemDLL("kernel32.dll")
	sndBeep     = sndKernel32.NewProc("Beep")
)

func beep(frequency, durationMs uint32) {
	sndBeep.Call(uintptr(frequency), uintptr(durationMs))
}

// PlayFeedback plays an audio cue asynchronously.
func PlayFeedback(soundType SoundType) {
	go func() {
		switch soundType {
		case SoundRecordStart:
			beep(800, 150)
		case SoundRecordStop:
			beep(600, 150)
		case SoundSuccess:
			beep(1000, 100)
			time.Sleep(50 * time.Millisecond)
			beep(1200, 100)
		case SoundError:
			beep(400, 300)
		}
	}()
}
