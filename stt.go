package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type LocalSTT struct {
	mu        sync.Mutex
	cmd       *exec.Cmd
	port      int
	running   bool
	modelPath string
}

var localSTT LocalSTT

// sttInferenceClient is reused for all STT inference requests (connection pooling).
var sttInferenceClient = &http.Client{Timeout: 120 * time.Second}

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
			return fmt.Sprintf("http://127.0.0.1:%d", s.port), nil
		}
		logInfo("STT model changed, restarting whisper-server")
		s.stopLocked()
	}

	serverPath, err := STTServerPath()
	if err != nil {
		return "", fmt.Errorf("stt server path: %w", err)
	}

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", fmt.Errorf("find free port: %w", err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()

	cmd := exec.Command(serverPath,
		"--model", modelPath,
		"--host", "127.0.0.1",
		"--port", fmt.Sprintf("%d", port),
		"--convert",
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start whisper-server: %w", err)
	}

	s.cmd = cmd
	s.port = port
	s.running = true
	s.modelPath = modelPath

	endpoint := fmt.Sprintf("http://127.0.0.1:%d", port)
	if err := s.waitReady(port); err != nil {
		s.stopLocked()
		return "", fmt.Errorf("whisper-server not ready: %w", err)
	}

	logInfo("Local STT started on port %d", port)
	return endpoint, nil
}

func (s *LocalSTT) waitReady(port int) error {
	healthURL := fmt.Sprintf("http://127.0.0.1:%d/health", port)
	client := &http.Client{Timeout: 2 * time.Second}
	for i := 0; i < 120; i++ {
		resp, err := client.Get(healthURL)
		if err == nil {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
			// 503 = model still loading — log periodically
			if i%10 == 9 {
				logInfo("STT server loading model... (%ds, status=%d, body=%s)", i+1, resp.StatusCode, string(body))
			}
		} else if i%10 == 9 {
			logInfo("STT server not reachable yet (%ds): %v", i+1, err)
		}
		time.Sleep(1 * time.Second)
	}
	return fmt.Errorf("timeout waiting for whisper-server (120s)")
}

func (s *LocalSTT) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

func (s *LocalSTT) stopLocked() {
	if !s.running || s.cmd == nil || s.cmd.Process == nil {
		s.running = false
		return
	}
	if err := s.cmd.Process.Kill(); err != nil {
		logWarn("Failed to kill whisper-server: %v", err)
	}
	s.cmd.Wait()
	s.running = false
	s.port = 0
	s.modelPath = ""
	logInfo("Local STT stopped")
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
	return fmt.Sprintf("http://127.0.0.1:%d", s.port)
}

func (s *LocalSTT) Transcribe(wavData []byte, lang string) (string, error) {
	s.mu.Lock()
	if !s.running {
		s.mu.Unlock()
		return "", fmt.Errorf("STT server not running")
	}
	port := s.port
	s.mu.Unlock()

	var body bytes.Buffer
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
	writer.WriteField("response_format", "json")
	writer.WriteField("temperature", "0.0")

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("close multipart writer: %w", err)
	}

	url := fmt.Sprintf("http://127.0.0.1:%d/inference", port)
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

	return strings.TrimSpace(result.Text), nil
}
