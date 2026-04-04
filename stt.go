package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/whispaste/whispaste/internal/gpu"
	"github.com/whispaste/whispaste/internal/inference"
)

type LocalSTT struct {
	mu              sync.Mutex
	cmd             *exec.Cmd
	port            int
	running         bool
	modelPath       string
	waitCh          chan error
	startupLog      *limitedProcessOutput
	cfg             *Config
	gpuModeOverride string
}

var localSTT LocalSTT

const maxWhisperStartupOutput = 8 * 1024

type limitedProcessOutput struct {
	mu   sync.Mutex
	data []byte
}

func (b *limitedProcessOutput) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	b.data = append(b.data, p...)
	if len(b.data) > maxWhisperStartupOutput {
		b.data = append([]byte(nil), b.data[len(b.data)-maxWhisperStartupOutput:]...)
	}
	return len(p), nil
}

func (b *limitedProcessOutput) Summary() string {
	if b == nil {
		return ""
	}

	b.mu.Lock()
	defer b.mu.Unlock()

	text := strings.Join(strings.Fields(string(b.data)), " ")
	text = strings.TrimSpace(text)
	if len(text) > 300 {
		text = "..." + text[len(text)-300:]
	}
	return text
}

// sttInferenceClient is reused for all STT inference requests (connection pooling).
// Custom transport: keep-alive for warm connections, no compression (localhost),
// generous idle pool so back-to-back dictations reuse the TCP connection.
var sttInferenceClient = &http.Client{
	Timeout: 120 * time.Second,
	Transport: &http.Transport{
		MaxIdleConns:        2,
		MaxIdleConnsPerHost: 2,
		IdleConnTimeout:     300 * time.Second,
		DisableCompression:  true, // localhost — compression wastes CPU
		ForceAttemptHTTP2:   false,
	},
}

func STTDir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, AppName, "models", "stt")
	return dir, os.MkdirAll(dir, 0700)
}

func STTServerPath() (string, error) {
	dir, err := STTDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "whisper-server.exe"), nil
}

func IsSTTServerInstalled() bool {
	p, err := STTServerPath()
	if err != nil {
		return false
	}
	_, err = os.Stat(p)
	return err == nil
}

func (s *LocalSTT) Start(modelPath string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.running {
		if s.modelPath == modelPath {
			logDebug("STT server already running (warm) on port %d", s.port)
			return fmt.Sprintf("http://%s:%d", loopbackHost, s.port), nil // DevSkim: ignore DS137138 — loopback-only, no TLS needed
		}
		logInfo("STT model changed, restarting whisper-server")
		s.stopLocked()
	}

	serverPath, err := STTServerPath()
	if err != nil {
		return "", fmt.Errorf("stt server path: %w", err)
	}
	if err := validateSTTStartupFiles(serverPath, modelPath); err != nil {
		return "", err
	}
	if err := ensureLocalSTTAllowed("", "use"); err != nil {
		return "", err
	}

	listener, err := net.Listen("tcp", loopbackHost+":0")
	if err != nil {
		return "", fmt.Errorf("find free port: %w", err)
	}
	tcpAddr, ok := listener.Addr().(*net.TCPAddr)
	if !ok {
		listener.Close()
		return "", fmt.Errorf("unexpected listener address type: %T", listener.Addr())
	}
	port := tcpAddr.Port
	listener.Close()

	gpuMode := s.gpuModeOverride
	if gpuMode == "" {
		gpuMode = "auto"
		if s.cfg != nil {
			gpuMode = s.cfg.GetGPUAcceleration()
		}
	}
	if err := EnsureSTTServerRuntime(gpuMode); err != nil {
		logInfo("STT runtime refresh failed, continuing with installed runtime: %v", err)
	}

	threads := sttThreadCount(gpuMode)
	backend := gpu.RecommendSTTBackend(gpuMode)
	cmd := exec.Command(serverPath, sttServerArgs(modelPath, port, threads, gpuMode)...)
	logInfo("Starting whisper-server with backend=%s and %d threads (logical CPUs: %d)", backend, threads, runtime.NumCPU())
	coldStartBegin := time.Now()
	logDebug("whisper-server command: %s", strings.Join(cmd.Args, " "))
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	startupLog := &limitedProcessOutput{}
	cmd.Stdout = startupLog
	cmd.Stderr = startupLog

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start whisper-server: %w", err)
	}

	s.cmd = cmd
	s.port = port
	s.running = true
	s.modelPath = modelPath
	s.startupLog = startupLog
	waitCh := make(chan error, 1)
	s.waitCh = waitCh
	go func(waitCh chan error) {
		waitCh <- cmd.Wait()
	}(waitCh)

	endpoint := fmt.Sprintf("http://%s:%d", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	if err := s.waitReady(port); err != nil {
		s.stopLocked()
		return "", fmt.Errorf("whisper-server not ready: %w", err)
	}

	logInfo("Local STT cold start completed in %v on port %d", time.Since(coldStartBegin), port)
	return endpoint, nil
}

func (s *LocalSTT) waitReady(port int) error {
	healthURL := fmt.Sprintf("http://%s:%d/health", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	client := &http.Client{Timeout: 2 * time.Second}
	lastErr := ""
	deadline := time.After(120 * time.Second)
	// Progressive backoff: check quickly at first (100ms), then slow down.
	// This shaves ~900ms off cold start compared to fixed 1s polling.
	interval := 100 * time.Millisecond
	maxInterval := 1 * time.Second
	iteration := 0
	for {
		select {
		case <-deadline:
			if lastErr != "" {
				return fmt.Errorf("timeout waiting for whisper-server (120s): %s", lastErr)
			}
			return fmt.Errorf("timeout waiting for whisper-server (120s)")
		case waitErr := <-s.waitCh:
			s.waitCh = nil
			exitMsg := whisperServerExitMessage(waitErr, s.startupLog.Summary())
			exitCode := extractExitCode(waitErr)
			if crashReporter != nil {
				crashReporter.captureSubprocessCrash("whisper-server", exitCode, s.startupLog.Summary())
			}
			return errors.New(exitMsg)
		default:
		}

		resp, err := client.Get(healthURL)
		if err == nil {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
			lastErr = fmt.Sprintf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
			if iteration%10 == 9 {
				logInfo("STT server loading model... (%ds, status=%d, body=%s)", iteration+1, resp.StatusCode, string(body))
			}
		} else {
			lastErr = err.Error()
			if iteration%10 == 9 {
				logInfo("STT server not reachable yet (%ds): %v", iteration+1, err)
			}
		}
		iteration++
		time.Sleep(interval)
		if interval < maxInterval {
			interval = interval * 3 / 2
			if interval > maxInterval {
				interval = maxInterval
			}
		}
	}
}

func (s *LocalSTT) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

func (s *LocalSTT) stopLocked() {
	if !s.running || s.cmd == nil || s.cmd.Process == nil {
		s.running = false
		s.cmd = nil
		s.port = 0
		s.modelPath = ""
		s.waitCh = nil
		s.startupLog = nil
		return
	}

	waitCh := s.waitCh
	s.waitCh = nil
	exited := false
	if waitCh != nil {
		select {
		case waitErr := <-waitCh:
			exited = true
			if waitErr != nil {
				logDebug("whisper-server already exited: %v", waitErr)
			}
		default:
		}
	}

	if !exited {
		if err := s.cmd.Process.Kill(); err != nil {
			if waitCh != nil {
				select {
				case waitErr := <-waitCh:
					exited = true
					if waitErr != nil {
						logDebug("whisper-server exited before kill completed: %v", waitErr)
					}
				case <-time.After(250 * time.Millisecond):
				}
			}
			if !exited && isAlreadyExitedProcessKillError(err) {
				exited = true
				logDebug("whisper-server already exited before kill: %v", err)
			}
			if !exited {
				logWarn("Failed to kill whisper-server: %v", err)
			}
		}
	}

	if !exited && waitCh != nil {
		select {
		case waitErr := <-waitCh:
			if waitErr != nil {
				logDebug("whisper-server wait after stop: %v", waitErr)
			}
		case <-time.After(2 * time.Second):
			logWarn("Timed out waiting for whisper-server to stop")
		}
	}

	s.running = false
	s.cmd = nil
	s.port = 0
	s.modelPath = ""
	s.startupLog = nil
	logInfo("Local STT stopped")
}

func whisperServerExitMessage(waitErr error, output string) string {
	msg := "whisper-server exited before becoming ready"
	if waitErr != nil {
		msg += ": " + waitErr.Error()
	} else {
		msg += " (exit code 0)"
	}
	if output != "" {
		msg += " (output: " + output + ")"
	}
	return msg
}

func isAlreadyExitedProcessKillError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, os.ErrProcessDone) {
		return true
	}
	if errors.Is(err, syscall.EINVAL) {
		return true
	}
	var errno syscall.Errno
	if errors.As(err, &errno) && errno == syscall.EINVAL {
		return true
	}
	return strings.Contains(strings.ToLower(err.Error()), "invalid argument")
}

func validateSTTStartupFiles(serverPath, modelPath string) error {
	if err := validateSTTStartupFile(serverPath, "whisper-server executable", "download the local transcription runtime again"); err != nil {
		return err
	}
	if err := validateSTTStartupFile(modelPath, "STT model file", "download the selected local model again"); err != nil {
		return err
	}
	return nil
}

func validateSTTStartupFile(path, label, hint string) error {
	info, err := os.Stat(path)
	if err == nil {
		if info.IsDir() {
			return fmt.Errorf("%s points to a directory: %s", label, path)
		}
		return nil
	}
	if os.IsNotExist(err) {
		return fmt.Errorf("%s not found at %s; %s", label, path, hint)
	}
	return fmt.Errorf("check %s at %s: %w", label, path, err)
}

func (s *LocalSTT) IsRunning() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running
}

func (s *LocalSTT) Endpoint() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.running {
		return ""
	}
	return fmt.Sprintf("http://%s:%d", loopbackHost, s.port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
}

func sttServerArgs(modelPath string, port int, threads int, gpuMode string) []string {
	args := []string{
		"--model", modelPath,
		"--host", loopbackHost,
		"--port", fmt.Sprintf("%d", port),
		"--threads", fmt.Sprintf("%d", threads),
	}
	if gpuMode == "disabled" {
		return append(args, "--no-gpu")
	}
	if gpu.RecommendSTTBackend(gpuMode) != gpu.BackendCPU {
		return append(args, "--flash-attn")
	}
	return args
}

// sttThreadCount returns the optimal thread count for whisper-server.
// CPU-only STT keeps one extra core free for capture/UI responsiveness.
func sttThreadCount(gpuMode string) int {
	if gpu.RecommendSTTBackend(gpuMode) == gpu.BackendCPU {
		return inference.STTThreadsCPUOnly()
	}
	return inference.STTThreads()
}

func (s *LocalSTT) Transcribe(wavData []byte, lang string, prompt ...string) (string, error) {
	s.mu.Lock()
	if !s.running {
		s.mu.Unlock()
		return "", fmt.Errorf("STT server not running")
	}
	port := s.port
	s.mu.Unlock()

	// Pre-size buffer: WAV data + ~512 bytes for multipart headers/fields
	var body bytes.Buffer
	body.Grow(len(wavData) + 512)
	writer := multipart.NewWriter(&body)

	part, err := writer.CreateFormFile("file", "audio.wav")
	if err != nil {
		return "", fmt.Errorf("create form file: %w", err)
	}
	if _, err := part.Write(wavData); err != nil {
		return "", fmt.Errorf("write wav data: %w", err)
	}

	if lang != "" {
		writer.WriteField("language", lang)
	}
	if len(prompt) > 0 && prompt[0] != "" {
		writer.WriteField("prompt", prompt[0])
	}
	writer.WriteField("response_format", "json")
	writer.WriteField("temperature", fmt.Sprintf("%.1f", inference.STTTemperature()))

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("close multipart writer: %w", err)
	}

	url := fmt.Sprintf("http://%s:%d/inference", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	logDebug("STT inference request: port=%d wavBytes=%d lang=%s", port, len(wavData), lang)
	start := time.Now()

	resp, err := sttInferenceClient.Post(url, writer.FormDataContentType(), &body)
	if err != nil {
		return "", fmt.Errorf("inference request (after %v): %w", time.Since(start), err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	logDebug("STT inference response: status=%d duration=%v bodyLen=%d", resp.StatusCode, time.Since(start), len(respBody))

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("inference failed (HTTP %d): %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("decode response: %w", err)
	}

	return normalizeTranscription(result.Text), nil
}
