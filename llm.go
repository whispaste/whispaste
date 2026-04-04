package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/whispaste/whispaste/internal/gpu"
	"github.com/whispaste/whispaste/internal/inference"
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
	waitCh  chan error // receives cmd.Wait() result for safe shutdown
	cfg     *Config    // set during init, used for model selection
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

// LLMModelPath returns the path to the supported GGUF model file.
func LLMModelPath(_ string) (string, error) {
	dir, err := LLMDir()
	if err != nil {
		return "", err
	}
	if m, ok := LLMModels[supportedLocalLLMModelID]; ok {
		return filepath.Join(dir, m.Filename), nil
	}
	return "", fmt.Errorf("unknown LLM model: %s", supportedLocalLLMModelID)
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

// IsLLMInstalled checks if llama-server.exe and the supported model exist.
func IsLLMInstalled() bool {
	if !IsLLMServerInstalled() {
		return false
	}
	return IsLLMModelInstalled(supportedLocalLLMModelID)
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

	gpuMode := "auto"
	if l.cfg != nil {
		gpuMode = l.cfg.GetGPUAcceleration()
	}
	if err := EnsureLLMServerRuntime(gpuMode); err != nil {
		logInfo("LLM runtime refresh failed, continuing with installed runtime: %v", err)
	}

	// #nosec G204 -- server path and args are constrained to app-managed binaries on loopback only.
	cmd := exec.CommandContext(context.Background(), serverPath, llmServerArgs(modelPath, port, gpuMode, selectedModel)...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("start llama-server: %w", err)
	}

	l.cmd = cmd
	l.port = port
	l.running = true

	// Monitor process exit for early failure detection
	l.waitCh = make(chan error, 1)
	go func() { l.waitCh <- cmd.Wait() }()

	// Wait for server to be ready (health check)
	endpoint := fmt.Sprintf("http://%s:%d/v1", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	if err := l.waitReady(port, l.waitCh); err != nil {
		l.stopLocked()
		return "", fmt.Errorf("llama-server not ready: %w", err)
	}

	logInfo("Local LLM started on port %d", port)
	return endpoint, nil
}

func llmServerArgs(modelPath string, port int, gpuMode string, selectedModel string) []string {
	args := []string{
		"--model", modelPath,
		"--host", loopbackHost,
		"--port", fmt.Sprintf("%d", port),
		"--ctx-size", "4096",
		"--threads", fmt.Sprintf("%d", inference.LLMThreads()),
		"--log-disable",
		"--parallel", "1",
		"--no-webui",
	}

	// Qwen3-family models can emit reasoning-only responses on the current
	// llama-server runtime unless reasoning is explicitly constrained.
	if llmNeedsReasoningBudgetZero(selectedModel, modelPath) {
		args = append(args, "--reasoning-budget", "0")
	}

	// Newer llama-server builds require an explicit value for flash attention.
	// "auto" still enables it on supported GPUs while keeping startup compatible.
	if gpu.ShouldUseRecommendedGPU(gpuMode) {
		args = append(args, "--n-gpu-layers", "-1", "--flash-attn", "auto")
	}

	return args
}

func llmNeedsReasoningBudgetZero(modelID string, modelPath string) bool {
	name := strings.ToLower(strings.TrimSpace(modelID))
	if name == "" {
		name = strings.ToLower(filepath.Base(modelPath))
	}
	return strings.Contains(name, "qwen3")
}

// waitReady polls the health endpoint until the server is ready.
// If the process exits early (e.g., wrong GPU binary), it returns immediately.
func (l *LocalLLM) waitReady(port int, waitCh <-chan error) error {
	healthURL := fmt.Sprintf("http://%s:%d/health", loopbackHost, port) // DevSkim: ignore DS137138 — loopback-only, no TLS needed
	client := &http.Client{Timeout: 2 * time.Second}
	for i := 0; i < 60; i++ {
		// Check if process died before becoming ready
		select {
		case err := <-waitCh:
			if crashReporter != nil {
				exitCode := extractExitCode(err)
				crashReporter.captureSubprocessCrash("llama-server", exitCode, "")
			}
			if err != nil {
				return fmt.Errorf("llama-server exited: %w", err)
			}
			return fmt.Errorf("llama-server exited unexpectedly")
		default:
		}

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
		l.waitCh = nil
		return
	}

	// Drain the waitCh goroutine — only one place calls cmd.Wait()
	waitCh := l.waitCh
	l.waitCh = nil

	// Check if the process already exited
	exited := false
	if waitCh != nil {
		select {
		case <-waitCh:
			exited = true
		default:
		}
	}

	if !exited {
		if err := l.cmd.Process.Kill(); err != nil {
			// Process may have exited between the check and kill (TOCTOU race)
			if waitCh != nil {
				select {
				case <-waitCh:
					exited = true
				case <-time.After(250 * time.Millisecond):
				}
			}
			if !exited && isAlreadyExitedProcessKillError(err) {
				exited = true
				logDebug("llama-server already exited before kill: %v", err)
			}
			if !exited {
				logWarn("Failed to kill llama-server: %v", err)
			}
		}
	}

	if !exited && waitCh != nil {
		select {
		case <-waitCh:
		case <-time.After(2 * time.Second):
			logWarn("Timed out waiting for llama-server to stop")
		}
	}

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

// migrateLegacyLLMModel migrates known config IDs to the supported model and
// refuses to relabel unknown legacy GGUF files as the current model.
func migrateLegacyLLMModel(cfg *Config) {
	if cfg != nil {
		cfg.mu.Lock()
		legacyID := strings.TrimSpace(cfg.LocalLLMModel)
		switch legacyID {
		case "qwen2.5-0.5b", "qwen3-0.6b", "smollm2":
			cfg.LocalLLMModel = supportedLocalLLMModelID
		}
		changed := cfg.LocalLLMModel == supportedLocalLLMModelID && legacyID != "" && legacyID != supportedLocalLLMModelID
		cfg.mu.Unlock()
		if changed {
			if err := cfg.Save(); err != nil {
				logWarn("Failed to persist local LLM model migration from %s to %s: %v", legacyID, supportedLocalLLMModelID, err)
			} else {
				logInfo("Migrated local LLM model config from %s to %s", legacyID, supportedLocalLLMModelID)
			}
		}
	}

	dir, err := LLMDir()
	if err != nil {
		return
	}
	for _, legacyName := range []string{"model.gguf", "qwen2.5-0.5b.gguf"} {
		legacyPath := filepath.Join(dir, legacyName)
		if _, err := os.Stat(legacyPath); err == nil && !IsLLMModelInstalled(supportedLocalLLMModelID) {
			logInfo("Detected unsupported legacy local LLM file %s; fresh download of %s is required", legacyName, supportedLocalLLMModelID)
		}
	}
}
