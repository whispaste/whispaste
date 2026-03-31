package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/i18n"
	"github.com/whispaste/whispaste/internal/inference"
	"github.com/whispaste/whispaste/internal/provider"
)

var multiSpace = regexp.MustCompile(`\s{2,}`)

// truncateForLog truncates a string to maxLen chars for log readability.
func truncateForLog(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "…"
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

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

var promptLanguageNames = map[string]string{
	"en":         "English",
	"english":    "English",
	"de":         "German",
	"deutsch":    "German",
	"german":     "German",
	"es":         "Spanish",
	"espanol":    "Spanish",
	"español":    "Spanish",
	"spanish":    "Spanish",
	"fr":         "French",
	"francais":   "French",
	"français":   "French",
	"french":     "French",
	"it":         "Italian",
	"italiano":   "Italian",
	"italian":    "Italian",
	"pt":         "Portuguese",
	"portugues":  "Portuguese",
	"português":  "Portuguese",
	"portuguese": "Portuguese",
	"ja":         "Japanese",
	"japanese":   "Japanese",
	"zh":         "Chinese",
	"chinese":    "Chinese",
	"ko":         "Korean",
	"korean":     "Korean",
	"ru":         "Russian",
	"russian":    "Russian",
}

// stripThinkBlocks removes <think>…</think> blocks that some LLMs (Qwen3+)
// emit in "thinking mode". The blocks waste tokens and pollute output.
func stripThinkBlocks(text string) string {
	text = thinkBlockRe.ReplaceAllString(text, "")
	return strings.TrimSpace(text)
}

func promptLanguageName(lang string) string {
	key := strings.ToLower(strings.TrimSpace(lang))
	if key == "" || key == "auto" {
		return ""
	}
	if mapped, ok := promptLanguageNames[key]; ok {
		return mapped
	}
	return strings.TrimSpace(lang)
}

func sameLanguageInstruction(langHint string) string {
	if languageName := promptLanguageName(langHint); languageName != "" {
		return fmt.Sprintf("The user's input is in %s. Keep the output in %s unless the instructions explicitly ask for translation.", languageName, languageName)
	}
	return "Keep the output in the same language as the user's input unless the instructions explicitly ask for translation."
}

func wrapSmartTransformPrompt(actionPrompt, langHint string) string {
	return fmt.Sprintf(`You are refining dictated text for a premium voice dictation app.

NON-NEGOTIABLE RULES:
1. Preserve the user's meaning, facts, names, numbers, dates, links, and intent.
2. Do not invent content or silently drop important information unless the instructions explicitly require shortening or summarizing.
3. %s
4. Return only the final text. No commentary, no quotes, no explanations.

TRANSFORMATION INSTRUCTIONS:
%s`, sameLanguageInstruction(langHint), strings.TrimSpace(actionPrompt))
}

// wrapSmartTransformPromptLocal creates a direct prompt for local LLMs (sub-1B params).
// Small models follow the first clear instruction they see, so we pass the preset's
// action prompt directly without a "refine" wrapper that could override it.
func wrapSmartTransformPromptLocal(actionPrompt, langHint string) string {
	langSuffix := ""
	if languageName := promptLanguageName(langHint); languageName != "" {
		langSuffix = fmt.Sprintf(" Keep the output in %s.", languageName)
	}
	return strings.TrimSpace(actionPrompt) + langSuffix + " Do not add any commentary or explanation."
}

func buildTranslatePrompt(targetLang string) string {
	target := promptLanguageName(normalizeSmartTargetLanguage(targetLang))
	return fmt.Sprintf(`Translate the following text into %s.

NON-NEGOTIABLE RULES:
1. Preserve meaning, facts, names, numbers, formatting cues, and tone as closely as possible.
2. Do not omit information or add explanations.
3. Return only the translation. No commentary, no quotes.`, target)
}

func resolveSmartActionPrompt(preset, customPrompt string, userTemplates map[string]string) string {
	if preset == "custom" && customPrompt != "" {
		return customPrompt
	}
	p, ok := smartModePresets[preset]
	if !ok && userTemplates != nil {
		if ut, found := userTemplates[preset]; found {
			p = ut
			ok = true
		}
	}
	if !ok {
		return ""
	}
	return p
}

// smartModePresets maps preset names to system prompts.
var smartModePresets = map[string]string{
	"cleanup":  "Clean up the following dictated text. Fix grammar, punctuation, capitalization, and spelling errors. Do not remove words, change meaning, or restructure sentences. Keep the original language. Return only the cleaned text.",
	"concise":  "Rewrite the following text to be more concise. Remove filler words, redundancy, and unnecessary repetition. Combine sentences where possible. Preserve all key information and meaning. Maintain the original language and tone. Return only the rewritten text.",
	"email":    "Rewrite the following dictated text as a complete professional email. You MUST include a suitable greeting at the beginning and a suitable closing at the end. Preserve all factual content, fix grammar and punctuation, and keep the original language. Return only the final email text.",
	"bullets":  "Rewrite the following dictated text as a structured bullet-point list. Fix grammar and punctuation. Keep the original language. Return only the bullet list.",
	"formal":   "Rewrite the following dictated text in formal, professional language. Fix grammar and punctuation. Keep the original language. Return only the rewritten text.",
	"aiprompt": "Rewrite the following dictated text as a clear instruction for an AI assistant. Remove filler words and hesitation. Keep all specific requirements and constraints. Use direct, imperative tone. Return only the instruction text.",
	"summary":  "Summarize the following text in 2–4 sentences maximum. Extract only the most essential points and core message. Drop all details. Fix grammar and punctuation. Keep the original language. Return only the summary.",
	"notes":    "Rewrite the following dictated text as structured notes. Use headings for topics and bullet points for details. Add action items where applicable. Fix grammar and punctuation. Keep the original language. Return only the notes.",
	"meeting":  "Rewrite the following dictated text as meeting minutes. Include: subject header, discussed topics, decisions made, and action items with owners if mentioned. Fix grammar and punctuation. Keep the original language. Return only the meeting minutes.",
	"social":   "Rewrite the following dictated text as a social media post. Make it engaging and concise. Add relevant emoji where appropriate. Keep the original language. Return only the post text.",
	"casual":   "Rewrite the following dictated text in a casual, conversational tone. Make it sound natural and friendly. Remove unnecessary formality. Keep the original language and meaning. Return only the rewritten text.",
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
	"cleanup":  {Description: "Fixes grammar, spelling, and punctuation — content and length stay untouched", Keywords: nil},
	"concise":  {Description: "Cuts redundancy and filler words — same message, fewer words", Keywords: nil},
	"email":    {Description: "Formats as a professional email with greeting, body, and sign-off", Keywords: []string{"*outlook*", "*thunderbird*", "*mail*", "*gmail*", "*yahoo*", "*proton*"}},
	"bullets":  {Description: "Flat bullet-point list without headings", Keywords: nil},
	"formal":   {Description: "Rewrites in formal, professional tone without changing the format", Keywords: nil},
	"aiprompt": {Description: "Optimized AI prompt", Keywords: []string{"*copilot*", "*chatgpt*", "*claude*", "*gemini*", "*cursor*", "*code*", "*visual studio*", "*intellij*", "*terminal*", "*powershell*"}},
	"summary":  {Description: "Extracts key points as a brief prose summary — details are dropped", Keywords: nil},
	"notes":    {Description: "Structured notes with headings, bullet points, and action items", Keywords: []string{"*notepad*", "*onenote*", "*obsidian*", "*notion*", "*evernote*", "*joplin*", "*typora*"}},
	"meeting":  {Description: "Formal minutes with subject, topics, decisions, and action items", Keywords: []string{"*teams*", "*zoom*", "*webex*", "*meet*", "*skype*"}},
	"social":   {Description: "Engaging social media post", Keywords: []string{"*twitter*", "*facebook*", "*instagram*", "*linkedin*", "*reddit*", "*tiktok*"}},
	"casual":   {Description: "Casual chat message", Keywords: []string{"*slack*", "*discord*", "*whatsapp*", "*telegram*", "*signal*", "*element*"}},
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

// localSmartMaxTokens caps max_tokens for local models to avoid generation
// timeouts on slower hardware (iGPU, CPU). Cloud models are fast enough that
// the profile's full MaxTokens is fine; local models generate tokens
// sequentially and need a tighter budget.
func localSmartMaxTokens(inputLen int, profile inference.Profile) int {
	// Rough estimate: 1 token ≈ 4 chars. Allow output ≈ input length + overhead.
	estimated := inputLen/4 + 128
	if estimated < 256 {
		estimated = 256
	}
	if estimated > profile.MaxTokens {
		estimated = profile.MaxTokens
	}
	return estimated
}

// PostProcess sends transcribed text through GPT-4o-mini for formatting/cleanup.
// endpoint should be the base API URL (e.g. "https://api.openai.com/v1").
// appLang is the UI language ("en" or "de") for language-aware prompts.
// userTemplates contains user-defined custom templates from config.
// localModelID is the local LLM model identifier (e.g. "qwen3.5-0.8b") — empty for cloud.
func PostProcess(text, preset, customPrompt, targetLang, apiKey, endpoint, langHint, localModelID string, userTemplates map[string]string) (string, error) {
	start := time.Now()
	systemPrompt := buildSmartPrompt(preset, customPrompt, targetLang, langHint, userTemplates)
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

	local := isLocalEndpoint(chatURL)
	profile := inference.ProfileForPreset(preset)
	modelName := "gpt-4o-mini"
	maxTokens := profile.MaxTokens
	if local {
		modelName = "local"
		maxTokens = localSmartMaxTokens(len(text), profile)
		// Rebuild prompt with simplified local variant for small models
		systemPrompt = buildSmartPromptLocal(preset, customPrompt, targetLang, langHint, userTemplates)
		if systemPrompt == "" {
			return text, nil
		}
		// Only Qwen3+ models support thinking mode — suppress it to save tokens/latency
		if strings.Contains(localModelID, "qwen3") {
			systemPrompt += " /no_think"
		}
	}

	logDebug("PostProcess: preset=%s local=%v input_len=%d max_tokens=%d prompt_len=%d", preset, local, len(text), maxTokens, len(systemPrompt))
	if local {
		logDebug("PostProcess: system_prompt=%q", truncateForLog(systemPrompt, 200))
	}

	reqBody := map[string]interface{}{
		"model": modelName,
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": text},
		},
		"temperature": profile.Temperature,
		"max_tokens":  maxTokens,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return text, fmt.Errorf("failed to marshal request: %w", err)
	}

	timeout := 30 * time.Second
	if local {
		timeout = 120 * time.Second
	}
	client := &http.Client{Timeout: timeout}
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return text, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		logDebug("PostProcess: failed after %s: %v", time.Since(start).Round(time.Millisecond), err)
		return text, fmt.Errorf("%s: %w", i18n.T("error.postprocess_request"), err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return text, fmt.Errorf("%s: %w", i18n.T("error.postprocess_request"), err)
	}

	if resp.StatusCode != http.StatusOK {
		logDebug("PostProcess: HTTP %d after %s", resp.StatusCode, time.Since(start).Round(time.Millisecond))
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
	cleaned := stripThinkBlocks(result.Choices[0].Message.Content)
	if cleaned == "" {
		logWarn("PostProcess: response contained only think blocks, using raw text")
		return text, fmt.Errorf("response contained only think blocks")
	}
	elapsed := time.Since(start).Round(time.Millisecond)
	logDebug("PostProcess: done in %s, output_len=%d output_preview=%q", elapsed, len(cleaned), truncateForLog(cleaned, 120))
	// Warn if local LLM returned text nearly identical to input (likely ignored the preset)
	if local && len(cleaned) > 0 && abs(len(cleaned)-len(text)) < len(text)/10 {
		logWarn("PostProcess: local LLM output length (%d) is very close to input (%d) — model may not have applied preset %q", len(cleaned), len(text), preset)
	}
	return cleaned, nil
}

// PostProcessWithProvider uses the provider interface for cloud LLM processing.
// This supports all providers (OpenAI, Anthropic, Gemini, Groq) via a unified interface.
func PostProcessWithProvider(text, preset, customPrompt, targetLang, langHint string, userTemplates map[string]string, llm provider.LLMProvider, dictionary string) (string, error) {
	systemPrompt := buildSmartPrompt(preset, customPrompt, targetLang, langHint, userTemplates)
	if systemPrompt == "" {
		return text, nil
	}

	// Inject custom dictionary into the system prompt
	if dictionary != "" {
		systemPrompt += fmt.Sprintf("\n\nIMPORTANT: The following specialized terms must be spelled correctly: %s", dictionary)
	}

	profile := inference.ProfileForPreset(preset)
	opts := provider.LLMOptions{
		Model:       "", // use provider default
		Temperature: profile.Temperature,
		MaxTokens:   profile.MaxTokens,
		TopP:        profile.TopP,
	}

	messages := []provider.Message{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: text},
	}

	result, err := llm.ChatCompletion(context.Background(), messages, opts)
	if err != nil {
		return text, fmt.Errorf("smart mode (%s): %w", llm.Name(), err)
	}
	if result == "" {
		return text, fmt.Errorf("%s", i18n.T("error.postprocess_empty"))
	}
	cleaned := stripThinkBlocks(result)
	if cleaned == "" {
		logWarn("PostProcessWithProvider: response contained only think blocks, using raw text")
		return text, fmt.Errorf("response contained only think blocks")
	}
	return cleaned, nil
}

// ApplySmartAction applies a smart mode preset or custom prompt to existing text.
// It reuses the same OpenAI Chat API as PostProcess.
func ApplySmartAction(text, preset, customPrompt, targetLang, apiKey, endpoint, langHint string, userTemplates map[string]string) (string, error) {
	return PostProcess(text, preset, customPrompt, targetLang, apiKey, endpoint, langHint, "", userTemplates)
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
func buildBulkSmartPrompt(preset, customPrompt, targetLang, langHint string, userTemplates map[string]string) string {
	// Resolve the action prompt
	var actionPrompt string
	if preset == "translate" {
		actionPrompt = buildTranslatePrompt(targetLang)
	} else {
		actionPrompt = resolveSmartActionPrompt(preset, customPrompt, userTemplates)
		if actionPrompt == "" {
			return ""
		}
	}
	if preset != "translate" {
		actionPrompt = wrapSmartTransformPrompt(actionPrompt, langHint)
	}

	return fmt.Sprintf(`You receive multiple numbered transcription segments from the same user. Your task has two parts:

STEP 1 — MERGE: Combine all segments into one coherent, flowing text. Preserve ALL information, facts, and statements from every segment. Do not drop, summarize, or reduce any content. Fix transitions so the result reads naturally as a single text.

STEP 2 — TRANSFORM: Apply the following transformation to the merged text:
%s

Return only the final transformed result. No explanations, no segment markers, no meta-commentary.`, actionPrompt)
}

func buildSmartPrompt(preset, customPrompt, targetLang, langHint string, userTemplates map[string]string) string {
	if preset == "system" && customPrompt != "" {
		return customPrompt
	}
	if preset == "translate" {
		return buildTranslatePrompt(targetLang)
	}
	actionPrompt := resolveSmartActionPrompt(preset, customPrompt, userTemplates)
	if actionPrompt == "" {
		return ""
	}
	return wrapSmartTransformPrompt(actionPrompt, langHint)
}

// buildSmartPromptLocal creates simplified prompts optimized for small local LLMs.
func buildSmartPromptLocal(preset, customPrompt, targetLang, langHint string, userTemplates map[string]string) string {
	if preset == "system" && customPrompt != "" {
		return customPrompt
	}
	if preset == "translate" {
		return buildTranslatePrompt(targetLang)
	}
	actionPrompt := resolveSmartActionPrompt(preset, customPrompt, userTemplates)
	if actionPrompt == "" {
		return ""
	}
	return wrapSmartTransformPromptLocal(actionPrompt, langHint)
}

// ApplyTextReplacementsWithAI runs exact replacements first, then uses AI (local or cloud)
// to find semantic matches for remaining trigger phrases.
// cloudLLMCreator is an optional factory that returns a cloud LLM provider for non-OpenAI routing.
func ApplyTextReplacementsWithAI(text string, replacements []TextReplacement, aiEnabled bool, providerMode string, cloudLLMCreator func() (provider.LLMProvider, error)) string {
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

	// Try cloud provider first if configured
	if providerMode == "cloud" && cloudLLMCreator != nil {
		llm, err := cloudLLMCreator()
		if err == nil {
			result, pErr := queryLLMForReplacementsWithProvider(llm, text, remaining)
			if pErr == nil {
				return result
			}
			logWarn("AI text replacement via cloud provider failed: %v, falling back", pErr)
		}
	}

	// Fallback: use local LLM
	if !IsLLMInstalled() {
		return text
	}
	ep, err := localLLM.Start()
	if err != nil {
		logWarn("AI text replacement: LLM start failed: %v", err)
		return text
	}

	aiResult, err := queryLLMForReplacements(ep, "local", text, remaining)
	if err != nil {
		logWarn("AI text replacement failed: %v", err)
		return text
	}

	return aiResult
}

// queryLLMForReplacementsWithProvider uses the provider abstraction for cloud LLM calls.
func queryLLMForReplacementsWithProvider(llm provider.LLMProvider, text string, replacements []TextReplacement) (string, error) {
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

	messages := []provider.Message{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: text},
	}
	opts := provider.LLMOptions{
		Temperature: inference.Factual.Temperature,
		MaxTokens:   len(text) + 200,
	}
	return llm.ChatCompletion(context.Background(), messages, opts)
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
		"temperature": inference.Factual.Temperature,
		"max_tokens":  len(text) + 200,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return text, fmt.Errorf("marshal request: %w", err)
	}

	timeout := 30 * time.Second
	if isLocalEndpoint(chatURL) {
		timeout = 120 * time.Second
	}
	client := &http.Client{Timeout: timeout}
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
