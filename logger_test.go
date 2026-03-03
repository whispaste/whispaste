package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoggerWritesToFile(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "test.log")

	l := &appLogger{level: LogDebug}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		t.Fatalf("OpenFile: %v", err)
	}
	l.file = f

	l.log(LogInfo, "INF", "test message %d", 42)
	f.Close()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "[INF]") {
		t.Errorf("log missing [INF] tag: %q", content)
	}
	if !strings.Contains(content, "test message 42") {
		t.Errorf("log missing message: %q", content)
	}
}

func TestLoggerLevelFiltering(t *testing.T) {
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "test.log")

	l := &appLogger{level: LogWarn}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
	if err != nil {
		t.Fatalf("OpenFile: %v", err)
	}
	l.file = f

	l.log(LogDebug, "DBG", "should be filtered")
	l.log(LogInfo, "INF", "should be filtered")
	l.log(LogWarn, "WRN", "should appear")
	l.log(LogError, "ERR", "should appear")
	f.Close()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	content := string(data)
	if strings.Contains(content, "should be filtered") {
		t.Error("debug/info messages should be filtered at LogWarn level")
	}
	if !strings.Contains(content, "should appear") {
		t.Error("warn/error messages should appear at LogWarn level")
	}
}

func TestLoggerNilFile(t *testing.T) {
	// Should not panic when file is nil (falls back to stderr)
	l := &appLogger{level: LogDebug}
	l.log(LogInfo, "INF", "test with nil file")
}

func TestLogLevelConstants(t *testing.T) {
	if LogDebug >= LogInfo {
		t.Error("LogDebug should be less than LogInfo")
	}
	if LogInfo >= LogWarn {
		t.Error("LogInfo should be less than LogWarn")
	}
	if LogWarn >= LogError {
		t.Error("LogWarn should be less than LogError")
	}
}
