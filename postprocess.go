package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

// smartModePresets maps preset names to system prompts.
var smartModePresets = map[string]string{
	"cleanup":   "Clean up the following dictated text. Fix grammar, punctuation, and capitalization. Remove filler words. Keep the original language and meaning. Return only the cleaned text.",
	"concise":   "Rewrite the following text more concisely. Keep the core message and all important information, but remove filler words, redundancy, and unnecessary verbosity. Maintain the original language and tone. Return only the rewritten text.",
	"email":     "Rewrite the following dictated text as a professional email. Use proper greeting and closing. Fix grammar and punctuation. Keep the original language. Return only the email text.",
	"bullets":   "Rewrite the following dictated text as a structured bullet-point list. Fix grammar and punctuation. Keep the original language. Return only the bullet list.",
	"formal":    "Rewrite the following dictated text in formal, professional language. Fix grammar and punctuation. Keep the original language. Return only the rewritten text.",
	"aiprompt":  "Transform the following dictated text into an optimized AI prompt. Identify the user's core intent and desired outcome. Remove filler words, hesitations, and redundancy. Restructure as clear, actionable instructions that an LLM can follow precisely. Use imperative tone. Prioritize token efficiency — every word must serve a purpose. Preserve all specific requirements, constraints, and context. Return only the prompt text.",
	"summary":   "Summarize the following dictated text concisely. Capture the key points and main ideas in a few sentences. Fix grammar and punctuation. Keep the original language. Return only the summary.",
	"notes":     "Rewrite the following dictated text as structured meeting notes or personal notes. Use headings for topics, bullet points for details, and action items where applicable. Fix grammar and punctuation. Keep the original language. Return only the notes.",
	"meeting":   "Rewrite the following dictated text as structured meeting minutes. Include: Date/Subject header, list of discussed topics, decisions made, and action items with owners if mentioned. Fix grammar and punctuation. Keep the original language. Return only the meeting minutes.",
	"social":    "Rewrite the following dictated text as a social media post. Make it engaging, concise, and attention-grabbing. Add relevant emoji where appropriate. Keep the original language. Return only the post text.",
	"technical": "Rewrite the following dictated text as technical documentation. Use clear, precise language. Structure with headings, code references where applicable, and step-by-step instructions if appropriate. Fix grammar and punctuation. Keep the original language. Return only the documentation.",
	"casual":    "Rewrite the following dictated text in a casual, conversational tone. Make it sound natural and friendly, like a chat message. Remove unnecessary formality. Keep the original language and meaning. Return only the rewritten text.",
}

// GetBuiltinPresets returns the built-in preset names and their prompts.
func GetBuiltinPresets() map[string]string {
	result := make(map[string]string, len(smartModePresets))
	for k, v := range smartModePresets {
		result[k] = v
	}
	return result
}

// defaultTemplateMetas provides default metadata and keywords for builtin presets.
var defaultTemplateMetas = map[string]TemplateMeta{
	"cleanup":   {Description: "General text cleanup and grammar correction", Keywords: nil},
	"concise":   {Description: "Rewrite text more concisely", Keywords: nil},
	"email":     {Description: "Professional email formatting", Keywords: []string{"*outlook*", "*thunderbird*", "*mail*", "*gmail*", "*yahoo*", "*proton*"}},
	"bullets":   {Description: "Structured bullet-point list", Keywords: nil},
	"formal":    {Description: "Formal professional language", Keywords: nil},
	"aiprompt":  {Description: "Optimized AI prompt", Keywords: []string{"*copilot*", "*chatgpt*", "*claude*", "*gemini*", "*cursor*"}},
	"summary":   {Description: "Concise summary of key points", Keywords: nil},
	"notes":     {Description: "Structured notes and bullet points", Keywords: []string{"*notepad*", "*onenote*", "*obsidian*", "*notion*", "*evernote*", "*joplin*", "*typora*"}},
	"meeting":   {Description: "Meeting minutes with action items", Keywords: []string{"*teams*", "*zoom*", "*webex*", "*meet*", "*skype*"}},
	"social":    {Description: "Engaging social media post", Keywords: []string{"*twitter*", "*facebook*", "*instagram*", "*linkedin*", "*reddit*", "*tiktok*"}},
	"technical": {Description: "Technical documentation", Keywords: []string{"*code*", "*visual studio*", "*intellij*", "*vim*", "*neovim*", "*sublime*", "*terminal*", "*powershell*", "*cmd*"}},
	"casual":    {Description: "Casual chat message", Keywords: []string{"*slack*", "*discord*", "*whatsapp*", "*telegram*", "*signal*", "*element*"}},
}

// GetDefaultTemplateMetas returns a copy of the default template metadata.
func GetDefaultTemplateMetas() map[string]TemplateMeta {
	result := make(map[string]TemplateMeta, len(defaultTemplateMetas))
	for k, v := range defaultTemplateMetas {
		result[k] = v
	}
	return result
}

// MatchTemplate finds the best template for the active application using keyword matching.
// Returns the preset name and true if a match was found.
func MatchTemplate(appName, windowTitle string, metas map[string]TemplateMeta) (string, bool) {
	if appName == "" && windowTitle == "" {
		return "", false
	}
	context := strings.ToLower(appName + " " + windowTitle)

	bestPreset := ""
	bestScore := 0

	for presetName, meta := range metas {
		if len(meta.Keywords) == 0 {
			continue
		}
		score := 0
		for _, kw := range meta.Keywords {
			pattern := strings.ToLower(kw)
			if matched, _ := filepath.Match(pattern, strings.ToLower(appName)); matched {
				score += 2
			}
			// Check substring for patterns like *outlook*
			if len(pattern) > 2 && pattern[0] == '*' && pattern[len(pattern)-1] == '*' {
				inner := pattern[1 : len(pattern)-1]
				if strings.Contains(context, inner) {
					score++
				}
			}
		}
		if score > bestScore {
			bestScore = score
			bestPreset = presetName
		}
	}

	if bestPreset != "" {
		logDebug("Template match: %s/%s → %s (score %d)", appName, windowTitle, bestPreset, bestScore)
		return bestPreset, true
	}
	return "", false
}

// PostProcess sends transcribed text through GPT-4o-mini for formatting/cleanup.
// endpoint should be the base API URL (e.g. "https://api.openai.com/v1").
// appLang is the UI language ("en" or "de") for language-aware prompts.
// userTemplates contains user-defined custom templates from config.
func PostProcess(text, preset, customPrompt, targetLang, apiKey, endpoint, appLang string, userTemplates map[string]string) (string, error) {
	systemPrompt := buildSmartPrompt(preset, customPrompt, targetLang, appLang, userTemplates)
	if systemPrompt == "" {
		return text, nil
	}

	chatURL := "https://api.openai.com/v1/chat/completions"
	if endpoint != "" {
		base := endpoint
		if idx := len(base) - len("/audio/transcriptions"); idx > 0 && base[idx:] == "/audio/transcriptions" {
			base = base[:idx]
		}
		// If the endpoint already ends with /chat/completions, use it as-is
		if strings.HasSuffix(base, "/chat/completions") {
			chatURL = base
		} else {
			chatURL = base + "/chat/completions"
		}
	}

	modelName := "gpt-4o-mini"
	if strings.Contains(chatURL, "127.0.0.1") {
		modelName = "local"
	}

	reqBody := map[string]interface{}{
		"model": modelName,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": text},
		},
		"temperature": 0.3,
		"max_tokens":  2048,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return text, fmt.Errorf("failed to marshal request: %w", err)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return text, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return text, fmt.Errorf("smart mode request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return text, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return text, fmt.Errorf("smart mode API error %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return text, fmt.Errorf("failed to parse response: %w", err)
	}
	if len(result.Choices) == 0 || result.Choices[0].Message.Content == "" {
		return text, fmt.Errorf("empty response from smart mode")
	}
	return result.Choices[0].Message.Content, nil
}

// ApplySmartAction applies a smart mode preset or custom prompt to existing text.
// It reuses the same OpenAI Chat API as PostProcess.
func ApplySmartAction(text, preset, customPrompt, apiKey, endpoint, appLang string, userTemplates map[string]string) (string, error) {
	return PostProcess(text, preset, customPrompt, "", apiKey, endpoint, appLang, userTemplates)
}

func buildSmartPrompt(preset, customPrompt, targetLang, appLang string, userTemplates map[string]string) string {
	if preset == "translate" {
		if targetLang == "" {
			targetLang = "English"
		}
		return fmt.Sprintf("Translate the following text to %s. Return only the translation, no explanations.", targetLang)
	}
	if preset == "custom" && customPrompt != "" {
		return customPrompt
	}
	p, ok := smartModePresets[preset]
	if !ok {
		// Check user-defined custom templates
		if userTemplates != nil {
			if ut, found := userTemplates[preset]; found {
				p = ut
				ok = true
			}
		}
	}
	if !ok {
		return ""
	}
	// Add language instruction based on app's UI language
	if appLang == "de" {
		p += " Respond in German."
	}
	return p
}
