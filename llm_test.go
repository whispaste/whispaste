package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLLMServerArgs_GPUUsesExplicitFlashAttnValue(t *testing.T) {
	args := llmServerArgs("model.gguf", 12345, "enabled", supportedLocalLLMModelID)

	flashIdx := -1
	for i, arg := range args {
		if arg == "--flash-attn" {
			flashIdx = i
			break
		}
	}

	if flashIdx == -1 {
		t.Fatalf("llmServerArgs() missing --flash-attn: %v", args)
	}
	if flashIdx+1 >= len(args) {
		t.Fatalf("llmServerArgs() passed bare --flash-attn without value: %v", args)
	}
	if args[flashIdx+1] != "auto" {
		t.Fatalf("llmServerArgs() flash-attn value = %q, want %q", args[flashIdx+1], "auto")
	}
}

func TestLLMServerArgs_CPUOmitsGPUFlags(t *testing.T) {
	args := llmServerArgs("model.gguf", 12345, "disabled", supportedLocalLLMModelID)
	for _, arg := range args {
		if arg == "--n-gpu-layers" || arg == "--flash-attn" {
			t.Fatalf("llmServerArgs(disabled) should not contain GPU-only flag %q: %v", arg, args)
		}
	}
}

func TestLLMServerArgs_Qwen3AddsReasoningBudgetZero(t *testing.T) {
	args := llmServerArgs("qwen3.5-0.8b.gguf", 12345, "enabled", "qwen3.5-0.8b")

	budgetIdx := -1
	for i, arg := range args {
		if arg == "--reasoning-budget" {
			budgetIdx = i
			break
		}
	}

	if budgetIdx == -1 {
		t.Fatalf("llmServerArgs() missing --reasoning-budget for qwen3: %v", args)
	}
	if budgetIdx+1 >= len(args) || args[budgetIdx+1] != "0" {
		t.Fatalf("llmServerArgs() reasoning budget = %v, want 0: %v", args[budgetIdx+1:], args)
	}
}

func TestLLMServerArgs_NonQwen3OmitsReasoningBudget(t *testing.T) {
	tests := []struct {
		name        string
		modelPath   string
		selectedLLM string
	}{
		{name: "blank model id with non-qwen3 path", modelPath: "custom-model.gguf", selectedLLM: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			args := llmServerArgs(tt.modelPath, 12345, "enabled", tt.selectedLLM)
			for _, arg := range args {
				if arg == "--reasoning-budget" {
					t.Fatalf("llmServerArgs(%q, %q) should not include --reasoning-budget: %v", tt.modelPath, tt.selectedLLM, args)
				}
			}
		})
	}
}

func TestLLMModelPathDefaultsToSupportedModel(t *testing.T) {
	appData := t.TempDir()
	t.Setenv("APPDATA", appData)

	got, err := LLMModelPath("")
	if err != nil {
		t.Fatalf("LLMModelPath() error = %v", err)
	}
	want := filepath.Join(appData, AppName, "models", "llm", LLMModels[supportedLocalLLMModelID].Filename)
	if got != want {
		t.Fatalf("LLMModelPath() = %q, want %q", got, want)
	}
}

func TestIsLLMInstalledRequiresSupportedModel(t *testing.T) {
	appData := t.TempDir()
	t.Setenv("APPDATA", appData)
	dir := filepath.Join(appData, AppName, "models", "llm")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatalf("mkdir llm dir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "llama-server.exe"), []byte("stub"), 0600); err != nil {
		t.Fatalf("write server: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "model.gguf"), []byte("legacy"), 0600); err != nil {
		t.Fatalf("write legacy model: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "qwen2.5-0.5b.gguf"), []byte("legacy"), 0600); err != nil {
		t.Fatalf("write legacy qwen2.5 model: %v", err)
	}
	if IsLLMInstalled() {
		t.Fatal("IsLLMInstalled() should ignore unsupported legacy models")
	}
	if err := os.WriteFile(filepath.Join(dir, LLMModels[supportedLocalLLMModelID].Filename), []byte("current"), 0600); err != nil {
		t.Fatalf("write supported model: %v", err)
	}
	if !IsLLMInstalled() {
		t.Fatal("IsLLMInstalled() should accept the supported qwen3.5 model")
	}
}
