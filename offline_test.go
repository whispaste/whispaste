package main

import (
	"errors"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/whispaste/whispaste/internal/models"
	preflightpkg "github.com/whispaste/whispaste/internal/preflight"
)

func TestNormalizeLanguage(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"auto", ""},
		{"", ""},
		{"en", "en"},
		{"de", "de"},
		{"ja", "ja"},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := normalizeLanguage(tt.input)
			if got != tt.want {
				t.Errorf("normalizeLanguage(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestTranscribeLocal_TooShort(t *testing.T) {
	_, err := TranscribeLocal([]byte{0x00}, 16000, "en", "whisper-base")
	if err == nil {
		t.Error("expected error for too-short audio")
	}
}

func TestTranscribeLocal_FailsFastWhenDependencyMissing(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(t *testing.T)
		wantError string
	}{
		{
			name: "missing server",
			setup: func(t *testing.T) {
				t.Helper()
			},
			wantError: "whisper-server executable not found",
		},
		{
			name: "missing model",
			setup: func(t *testing.T) {
				t.Helper()
				serverPath, err := STTServerPath()
				if err != nil {
					t.Fatalf("STTServerPath: %v", err)
				}
				if err := os.WriteFile(serverPath, []byte("stub"), 0600); err != nil {
					t.Fatalf("WriteFile(%s): %v", serverPath, err)
				}
			},
			wantError: "STT model file not found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("APPDATA", t.TempDir())
			localSTT = LocalSTT{}
			tt.setup(t)

			_, err := TranscribeLocal([]byte{0x00, 0x01}, 16000, "en", "whisper-base")
			if err == nil {
				t.Fatal("expected dependency validation error")
			}
			if !strings.Contains(err.Error(), tt.wantError) {
				t.Fatalf("TranscribeLocal error = %q, want substring %q", err.Error(), tt.wantError)
			}
		})
	}
}

func TestLocalSTTWaitReady_FailsFastWhenProcessExits(t *testing.T) {
	waitCh := make(chan error, 1)
	waitCh <- errors.New("exit status 1")
	startupLog := &limitedProcessOutput{}
	if _, err := startupLog.Write([]byte("missing runtime dependency")); err != nil {
		t.Fatalf("startupLog.Write: %v", err)
	}
	stt := &LocalSTT{waitCh: waitCh, startupLog: startupLog}

	start := time.Now()
	err := stt.waitReady(65535)
	if err == nil {
		t.Fatal("expected waitReady to fail when process exits")
	}
	if !strings.Contains(err.Error(), "whisper-server exited before becoming ready") {
		t.Fatalf("waitReady error = %q", err.Error())
	}
	if !strings.Contains(err.Error(), "missing runtime dependency") {
		t.Fatalf("waitReady error should include captured startup output, got %q", err.Error())
	}
	if time.Since(start) > 250*time.Millisecond {
		t.Fatalf("waitReady should fail immediately when process has already exited")
	}
}

func TestTranscribeLocal_FailsFastWhenPreflightBlocks(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	localSTT = LocalSTT{}

	serverPath, err := STTServerPath()
	if err != nil {
		t.Fatalf("STTServerPath: %v", err)
	}
	if err := os.WriteFile(serverPath, []byte("stub"), 0600); err != nil {
		t.Fatalf("WriteFile(server): %v", err)
	}

	modelPath, err := STTModelPath("whisper-base")
	if err != nil {
		t.Fatalf("STTModelPath: %v", err)
	}
	if err := os.WriteFile(modelPath, []byte("stub"), 0600); err != nil {
		t.Fatalf("WriteFile(model): %v", err)
	}

	origPreflight := runLocalSTTPreflight
	runLocalSTTPreflight = func(modelID, purpose string) preflightpkg.Result {
		return preflightpkg.Result{
			Status:     preflightpkg.StatusFail,
			Blocking:   true,
			ReasonCode: "cpu-avx",
		}
	}
	t.Cleanup(func() { runLocalSTTPreflight = origPreflight })

	_, err = TranscribeLocal([]byte{0x00, 0x01}, 16000, "en", "whisper-base")
	if err == nil {
		t.Fatal("expected preflight error")
	}
	if !strings.Contains(err.Error(), "AVX") {
		t.Fatalf("TranscribeLocal error = %q, want AVX preflight detail", err.Error())
	}
}

func TestDefaultLocalSTTPreflight_DownloadedModelDoesNotRequireModelBytes(t *testing.T) {
	t.Setenv("APPDATA", t.TempDir())
	models.Init(AppName)

	serverPath, err := STTServerPath()
	if err != nil {
		t.Fatalf("STTServerPath: %v", err)
	}
	if err := os.WriteFile(serverPath, []byte("stub"), 0600); err != nil {
		t.Fatalf("WriteFile(server): %v", err)
	}

	modelPath, err := STTModelPath("whisper-base")
	if err != nil {
		t.Fatalf("STTModelPath: %v", err)
	}

	withoutDownload := defaultLocalSTTPreflight("whisper-base", "download")

	if err := os.WriteFile(modelPath, []byte("stub"), 0600); err != nil {
		t.Fatalf("WriteFile(model): %v", err)
	}

	withDownload := defaultLocalSTTPreflight("whisper-base", "download")

	if withDownload.Facts.RequiredBytes >= withoutDownload.Facts.RequiredBytes {
		t.Fatalf("downloaded model should reduce required bytes: with=%d without=%d", withDownload.Facts.RequiredBytes, withoutDownload.Facts.RequiredBytes)
	}
}

func TestIsAlreadyExitedProcessKillError(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{name: "nil", err: nil, want: false},
		{name: "process done", err: os.ErrProcessDone, want: true},
		{name: "windows invalid argument", err: errors.New("invalid argument"), want: true},
		{name: "wrapped syscall invalid argument", err: &os.SyscallError{Syscall: "TerminateProcess", Err: syscall.EINVAL}, want: true},
		{name: "other error", err: errors.New("access denied"), want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := isAlreadyExitedProcessKillError(tt.err); got != tt.want {
				t.Fatalf("isAlreadyExitedProcessKillError(%v) = %v, want %v", tt.err, got, tt.want)
			}
		})
	}
}
