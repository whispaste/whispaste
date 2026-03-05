package main

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// LocalLLM manages the llama-server subprocess for local text processing.
type LocalLLM struct {
	mu      sync.Mutex
	cmd     *exec.Cmd
	port    int
	running bool
}

var localLLM LocalLLM

// LLMDir returns the directory for LLM files (%APPDATA%\WhisPaste\models\llm).
func LLMDir() (string, error) {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return "", fmt.Errorf("APPDATA environment variable not set")
	}
	dir := filepath.Join(appData, AppName, "models", "llm")
	return dir, os.MkdirAll(dir, 0700)
}

// LLMServerPath returns the path to llama-server.exe.
func LLMServerPath() (string, error) {
	dir, err := LLMDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "llama-server.exe"), nil
}

// LLMModelPath returns the path to the GGUF model file.
func LLMModelPath() (string, error) {
	dir, err := LLMDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "model.gguf"), nil
}

// IsLLMInstalled checks if both llama-server.exe and model.gguf exist.
func IsLLMInstalled() bool {
	serverPath, err := LLMServerPath()
	if err != nil {
		return false
	}
	modelPath, err := LLMModelPath()
	if err != nil {
		return false
	}
	if _, err := os.Stat(serverPath); err != nil {
		return false
	}
	if _, err := os.Stat(modelPath); err != nil {
		return false
	}
	return true
}

// Start starts the llama-server subprocess on a random port.
// Returns the localhost endpoint URL or an error.
func (l *LocalLLM) Start() (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.running {
		return fmt.Sprintf("http://127.0.0.1:%d/v1", l.port), nil
	}

	serverPath, err := LLMServerPath()
	if err != nil {
		return "", fmt.Errorf("llm server path: %w", err)
	}
	modelPath, err := LLMModelPath()
	if err != nil {
		return "", fmt.Errorf("llm model path: %w", err)
	}

	// Find a free port
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
		"--ctx-size", "2048",
		"--threads", "4",
		"--log-disable",
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start llama-server: %w", err)
	}

	l.cmd = cmd
	l.port = port
	l.running = true

	// Wait for server to be ready (health check)
	endpoint := fmt.Sprintf("http://127.0.0.1:%d/v1", port)
	if err := l.waitReady(port); err != nil {
		l.stopLocked()
		return "", fmt.Errorf("llama-server not ready: %w", err)
	}

	logInfo("Local LLM started on port %d", port)
	return endpoint, nil
}

// waitReady polls the health endpoint until the server is ready.
func (l *LocalLLM) waitReady(port int) error {
	healthURL := fmt.Sprintf("http://127.0.0.1:%d/health", port)
	client := &http.Client{Timeout: 2 * time.Second}
	for i := 0; i < 60; i++ {
		resp, err := client.Get(healthURL)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
		}
		time.Sleep(1 * time.Second)
	}
	return fmt.Errorf("timeout waiting for llama-server")
}

// Stop kills the llama-server subprocess.
func (l *LocalLLM) Stop() {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.stopLocked()
}

func (l *LocalLLM) stopLocked() {
	if !l.running || l.cmd == nil || l.cmd.Process == nil {
		l.running = false
		return
	}
	if err := l.cmd.Process.Kill(); err != nil {
		logWarn("Failed to kill llama-server: %v", err)
	}
	l.cmd.Wait()
	l.running = false
	l.port = 0
	logInfo("Local LLM stopped")
}

// IsRunning returns whether the subprocess is currently running.
func (l *LocalLLM) IsRunning() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.running
}

// Endpoint returns the current localhost endpoint, or empty if not running.
func (l *LocalLLM) Endpoint() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	if !l.running {
		return ""
	}
	return fmt.Sprintf("http://127.0.0.1:%d/v1", l.port)
}
