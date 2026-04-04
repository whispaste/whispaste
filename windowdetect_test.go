//go:build windows

package main

import "testing"

func TestGetActiveAppName(t *testing.T) {
	// Smoke test — function should not panic even when called from a test harness
	// where there may not be a foreground window.
	name := GetActiveAppName()
	// Result may be "" in CI/headless but should never panic.
	_ = name
}

func TestGetActiveWindowTitle(t *testing.T) {
	title := GetActiveWindowTitle()
	_ = title
}
