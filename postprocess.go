package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/i18n"
)

var multiSpace = regexp.MustCompile(`\s{2,}`)

// isLocalEndpoint checks if a URL points to a local LLM/STT server.
// Used to distinguish local model requests from cloud API requests.
func isLocalEndpoint(url string) bool {
	return strings.Contains(url, "127.0.0.1") || strings.Contains(url, "localhost") // DevSkim: ignore DS162092 — production loopback detection for local AI servers
}

// normalizeTranscription removes artificial line breaks that whisper inserts
// at segment boundaries and collapses resulting multi-spaces.
func normalizeTranscription(text string) string {
	text = strings.ReplaceAll(text, "\r\n", " ")
	text = strings.ReplaceAll(text, "\n", " ")
	text = multiSpace.ReplaceAllString(text, " ")
	return strings.TrimSpace(text)
}

var thinkBlockRe = regexp.MustCompile(`(?s)<think>.*?</think>`)

// stripThinkBlocks removes <think>…</think> blocks that some LLMs (Qwen3+)
// emit in "thinking mode". The blocks waste tokens and pollute output.
func stripThinkBlocks(text string) string {
	text = thinkBlockRe.ReplaceAllString(text, "")
	return strings.TrimSpace(text)
}

// smartModePresets maps preset names to system prompts.
var smartModePresets = map[string]string{
	"cleanup":   "Clean up the following dictated text. Fix grammar, punctuation, capitalization, and spelling errors. Do not remove words, change meaning, or restructure sentences. Keep the original language. Return only the cleaned text.",
	"concise":   "Rewrite the following text to be significantly more concise. Aggressively remove filler words, redundancy, and unnecessary verbosity. Combine sentences where possible. The result should be roughly 60–70% of the original length while preserving ALL information and meaning. Maintain the original language and tone. Return only the rewritten text.",
	"email":     "Rewrite the following dictated text as a professional email. Use proper greeting and closing. Fix grammar and punctuation. Keep the original language. Return only the email text.",
	"bullets":   "Rewrite the following dictated text as a structured bullet-point list. Fix grammar and punctuation. Keep the original language. Return only the bullet list.",
	"formal":    "Rewrite the following dictated text in formal, professional language. Fix grammar and punctuation. Keep the original language. Return only the rewritten text.",
	"aiprompt":  "Transform the following dictated text into an optimized AI prompt. Identify the user's core intent and desired outcome. Remove filler words, hesitations, and redundancy. Restructure as clear, actionable instructions that an LLM can follow precisely. Use imperative tone. Prioritize token efficiency — every word must serve a purpose. Preserve all specific requirements, constraints, and context. Return only the prompt text.",
	"summary":   "Summarize the following text in 2–4 sentences maximum, regardless of input length. Extract only the most essential points and core message. This is a summary, not an edit — the output should be dramatically shorter than the input. Fix grammar and punctuation. Keep the original language. Return only the summary.",
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
	"cleanup":   {Description: "Fixes grammar, spelling, and punctuation — content and length stay untouched", Keywords: nil},
	"concise":   {Description: "Cuts redundancy and filler words — same message, fewer words", Keywords: nil},
	"email":     {Description: "Formats as a professional email with greeting, body, and sign-off", Keywords: []string{"*outlook*", "*thunderbird*", "*mail*", "*gmail*", "*yahoo*", "*proton*"}},
	"bullets":   {Description: "Flat bullet-point list without headings", Keywords: nil},
	"formal":    {Description: "Rewrites in formal, professional tone without changing the format", Keywords: nil},
	"aiprompt":  {Description: "Optimized AI prompt", Keywords: []string{"*copilot*", "*chatgpt*", "*claude*", "*gemini*", "*cursor*"}},
	"summary":   {Description: "Extracts key points as a brief prose summary — details are dropped", Keywords: nil},
	"notes":     {Description: "Flexible personal notes with headings and bullet points — quick reference", Keywords: []string{"*notepad*", "*onenote*", "*obsidian*", "*notion*", "*evernote*", "*joplin*", "*typora*"}},
	"meeting":   {Description: "Formal minutes with date, topics, decisions, and action items", Keywords: []string{"*teams*", "*zoom*", "*webex*", "*meet*", "*skype*"}},
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
	if isLocalEndpoint(chatURL) {
		modelName = "local"
		// Suppress thinking mode for local Qwen models to save tokens/latency
		systemPrompt += " /no_think"
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
		return text, fmt.Errorf("%s: %w", i18n.T("error.postprocess_request"), err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return text, fmt.Errorf("%s: %w", i18n.T("error.postprocess_request"), err)
	}

	if resp.StatusCode != http.StatusOK {
		return text, fmt.Errorf(i18n.T("error.postprocess_api")+" (%s)", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return text, fmt.Errorf("%s: %w", i18n.T("error.postprocess_parse"), err)
	}
	if len(result.Choices) == 0 || result.Choices[0].Message.Content == "" {
		return text, fmt.Errorf("%s", i18n.T("error.postprocess_empty"))
	}
	return stripThinkBlocks(result.Choices[0].Message.Content), nil
}

// ApplySmartAction applies a smart mode preset or custom prompt to existing text.
// It reuses the same OpenAI Chat API as PostProcess.
func ApplySmartAction(text, preset, customPrompt, apiKey, endpoint, appLang string, userTemplates map[string]string) (string, error) {
	return PostProcess(text, preset, customPrompt, "", apiKey, endpoint, appLang, userTemplates)
}

// joinTextsForBulk joins multiple transcription texts with numbered separators.
func joinTextsForBulk(texts []string) string {
	var sb strings.Builder
	for i, t := range texts {
		if i > 0 {
			sb.WriteString("\n\n")
		}
		fmt.Fprintf(&sb, "[%d] %s", i+1, strings.TrimSpace(t))
	}
	return sb.String()
}

// buildBulkSmartPrompt creates a compound prompt that instructs the LLM to
// merge multiple transcriptions coherently and then apply the preset transformation.
func buildBulkSmartPrompt(preset, customPrompt, appLang string, userTemplates map[string]string) string {
	// Resolve the action prompt
	var actionPrompt string
	if preset == "translate" {
		actionPrompt = "Translate the combined text to English. Return only the translation."
	} else if preset == "custom" && customPrompt != "" {
		actionPrompt = customPrompt
	} else {
		p, ok := smartModePresets[preset]
		if !ok && userTemplates != nil {
			p, ok = userTemplates[preset]
		}
		if !ok {
			return ""
		}
		actionPrompt = p
	}

	langInstruction := ""
	if appLang == "de" {
		langInstruction = " Respond in German."
	}

	return fmt.Sprintf(`You receive multiple numbered transcription segments from the same user. Your task has two parts:

STEP 1 — MERGE: Combine all segments into one coherent, flowing text. Preserve ALL information, facts, and statements from every segment. Do not drop, summarize, or reduce any content. Fix transitions so the result reads naturally as a single text.

STEP 2 — TRANSFORM: Apply the following transformation to the merged text:
%s

Return only the final transformed result. No explanations, no segment markers, no meta-commentary.%s`, actionPrompt, langInstruction)
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
	// Prepend strong language instruction for non-English UI languages.
	// Small local LLMs ignore weak trailing instructions — front-loading works.
	if appLang == "de" {
		p = "WICHTIG: Antworte IMMER auf Deutsch. " + p
	}
	return p
}

// ApplyTextReplacementsWithAI runs exact replacements first, then uses AI (local or cloud)
// to find semantic matches for remaining trigger phrases.
func ApplyTextReplacementsWithAI(text string, replacements []TextReplacement, aiEnabled bool, provider, apiKey, cloudEndpoint string) string {
	if len(replacements) == 0 {
		return text
	}

	// First pass: exact string replacements
	remaining := make([]TextReplacement, 0)
	for _, r := range replacements {
		if !r.Enabled || r.Trigger == "" {
			continue
		}
		if strings.Contains(text, r.Trigger) {
			text = strings.ReplaceAll(text, r.Trigger, r.Replacement)
		} else {
			remaining = append(remaining, r)
		}
	}

	// Second pass: AI semantic matching (only for triggers not found literally)
	if !aiEnabled || len(remaining) == 0 {
		return text
	}

	var llmEndpoint, llmAPIKey string
	if provider == "cloud" && apiKey != "" {
		// Use cloud API for semantic matching
		base := cloudEndpoint
		if idx := len(base) - len("/audio/transcriptions"); idx >= 0 && base[idx:] == "/audio/transcriptions" {
			base = base[:idx]
		}
		llmEndpoint = base
		llmAPIKey = apiKey
	} else {
		// Default: use local LLM
		if !IsLLMInstalled() {
			return text
		}
		ep, err := localLLM.Start()
		if err != nil {
			logWarn("AI text replacement: LLM start failed: %v", err)
			return text
		}
		llmEndpoint = ep
		llmAPIKey = "local"
	}

	aiResult, err := queryLLMForReplacements(llmEndpoint, llmAPIKey, text, remaining)
	if err != nil {
		logWarn("AI text replacement failed: %v", err)
		return text
	}

	return aiResult
}

func queryLLMForReplacements(llmEndpoint, apiKey, text string, replacements []TextReplacement) (string, error) {
	chatURL := llmEndpoint + "/chat/completions"

	modelName := "local"
	if !isLocalEndpoint(chatURL) {
		modelName = "gpt-4o-mini"
	}

	// Build the replacement rules description
	var rules strings.Builder
	for i, r := range replacements {
		fmt.Fprintf(&rules, "%d. When the text semantically mentions \"%s\" → replace with \"%s\"\n", i+1, r.Trigger, r.Replacement)
	}

	systemPrompt := fmt.Sprintf(`You are a text replacement assistant. Apply semantic replacements to the user's text.

RULES:
%s
INSTRUCTIONS:
1. Read the user's text carefully
2. For each rule, check if the text SEMANTICALLY contains the trigger phrase (not just literally — the meaning must match)
3. If a trigger phrase is semantically present, replace that part of the text with the replacement value
4. Preserve the rest of the text exactly as-is (formatting, punctuation, capitalization)
5. If no triggers match semantically, return the text unchanged
6. Return ONLY the modified text, nothing else — no explanations, no quotes

IMPORTANT: Only replace when the meaning clearly matches. When in doubt, do NOT replace.`, rules.String())

	// Suppress thinking mode for local models
	if isLocalEndpoint(chatURL) {
		systemPrompt += " /no_think"
	}

	reqBody := map[string]interface{}{
		"model": modelName,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": text},
		},
		"temperature": 0.0,
		"max_tokens":  len(text) + 200,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return text, fmt.Errorf("marshal request: %w", err)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return text, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return text, fmt.Errorf("LLM request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return text, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return text, fmt.Errorf("LLM returned status %d", resp.StatusCode)
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return text, fmt.Errorf("parse response: %w", err)
	}
	if len(result.Choices) == 0 {
		return text, fmt.Errorf("empty response from LLM")
	}

	modified := stripThinkBlocks(result.Choices[0].Message.Content)
	if modified == "" {
		return text, nil
	}
	// Guard against LLM truncation/hallucination
	if len(modified) < len(text)/2 {
		logWarn("AI text replacement: response too short (%d vs %d chars), keeping original", len(modified), len(text))
		return text, nil
	}
	return modified, nil
}
