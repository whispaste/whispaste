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

// loopbackHost is the bind address for local AI servers (LLM, STT).
// Intentionally hardcoded to loopback — these servers must never be
// exposed on the network.
const loopbackHost = "127.0.0.1" // DevSkim: ignore DS162092 — production loopback bind for local AI servers

// LocalLLM manages the llama-server subprocess for local text processing.
type LocalLLM struct {
	mu      sync.Mutex
	cmd     *exec.Cmd
	port    int
	running bool
	cfg     *Config // set during init, used for model selection
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

// LLMModelPath returns the path to the GGUF model file for the given model ID.
// Falls back to legacy model.gguf, then default "smollm2".
func LLMModelPath(modelID string) (string, error) {
	dir, err := LLMDir()
	if err != nil {
		return "", err
	}
	// If a specific model is requested, use its filename
	if modelID != "" {
		if m, ok := LLMModels[modelID]; ok {
			p := filepath.Join(dir, m.Filename)
			if _, err := os.Stat(p); err == nil {
				return p, nil
			}
		}
	}
	// Legacy: if model.gguf exists, use it (pre-registry installs)
	legacy := filepath.Join(dir, "model.gguf")
	if _, err := os.Stat(legacy); err == nil {
		return legacy, nil
	}
	// Deterministic fallback: check smollm2 first, then qwen3.5
	for _, id := range []string{"smollm2", "qwen3.5-0.8b"} {
		if m, ok := LLMModels[id]; ok {
			p := filepath.Join(dir, m.Filename)
			if _, err := os.Stat(p); err == nil {
				return p, nil
			}
		}
	}
	return filepath.Join(dir, "model.gguf"), nil
}

// LLMModelPathForID returns the model path for a specific model ID.
func LLMModelPathForID(modelID string) (string, error) {
	model, ok := LLMModels[modelID]
	if !ok {
		return "", fmt.Errorf("unknown LLM model: %s", modelID)
	}
	dir, err := LLMDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, model.Filename), nil
}

// IsLLMInstalled checks if llama-server.exe and at least one model exist.
func IsLLMInstalled() bool {
	if !IsLLMServerInstalled() {
		return false
	}
	dir, err := LLMDir()
	if err != nil {
		return false
	}
	// Check legacy model.gguf
	if _, err := os.Stat(filepath.Join(dir, "model.gguf")); err == nil {
		return true
	}
	// Check any registered model
	for _, m := range LLMModels {
		if _, err := os.Stat(filepath.Join(dir, m.Filename)); err == nil {
			return true
		}
	}
	return false
}

// Start starts the llama-server subprocess on a random port.
// Returns the loopback endpoint URL or an error.
func (l *LocalLLM) Start() (string, error) {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.running {
		return fmt.Sprintf("http://%s:%d/v1", loopbackHost, l.port), nil // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	}

	serverPath, err := LLMServerPath()
	if err != nil {
		return "", fmt.Errorf("llm server path: %w", err)
	}
	selectedModel := ""
	if l.cfg != nil {
		selectedModel = l.cfg.GetLocalLLMModel()
	}
	modelPath, err := LLMModelPath(selectedModel)
	if err != nil {
		return "", fmt.Errorf("llm model path: %w", err)
	}

	// Find a free port
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

	cmd := exec.Command(serverPath,
		"--model", modelPath,
		"--host", loopbackHost,
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
	endpoint := fmt.Sprintf("http://%s:%d/v1", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	if err := l.waitReady(port); err != nil {
		l.stopLocked()
		return "", fmt.Errorf("llama-server not ready: %w", err)
	}

	logInfo("Local LLM started on port %d", port)
	return endpoint, nil
}

// waitReady polls the health endpoint until the server is ready.
func (l *LocalLLM) waitReady(port int) error {
	healthURL := fmt.Sprintf("http://%s:%d/health", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
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
	return fmt.Sprintf("http://%s:%d/v1", loopbackHost, l.port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
}

// migrateLegacyLLMModel renames legacy model.gguf to smollm2.gguf for the new registry.
func migrateLegacyLLMModel() {
	dir, err := LLMDir()
	if err != nil {
		return
	}
	legacy := filepath.Join(dir, "model.gguf")
	if _, err := os.Stat(legacy); err != nil {
		return // no legacy file
	}
	target := filepath.Join(dir, LLMModels["smollm2"].Filename)
	if _, err := os.Stat(target); err == nil {
		os.Remove(legacy) // target already exists, just clean up
		return
	}
	if err := os.Rename(legacy, target); err != nil {
		logWarn("Failed to migrate legacy LLM model: %v", err)
		return
	}
	logInfo("Migrated legacy model.gguf to %s", LLMModels["smollm2"].Filename)
}
