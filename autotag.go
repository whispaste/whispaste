package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/whispaste/whispaste/internal/inference"
)

// timeAdjacentRe matches am/pm after a digit (e.g. "10 am", "3pm").
// Only digit→am/pm direction to avoid German "am 5." (ordinal) false positives.
var timeAdjacentRe = regexp.MustCompile(`\d\s*(?:am|pm)\b`)

// systemTags are internal tags managed by the application.
// They must never be auto-assigned or suggested by the LLM.
var systemTags = map[string]bool{
	"pending":    true,
	"duplicated": true,
}

// autoTagClient is a reusable HTTP client for LLM tagging requests.
var (
	autoTagClient     *http.Client
	autoTagClientOnce sync.Once
)

func getAutoTagClient() *http.Client {
	autoTagClientOnce.Do(func() {
		autoTagClient = &http.Client{Timeout: 120 * time.Second}
	})
	return autoTagClient
}

// AutoTagEntry uses the local LLM to assign tags to a history entry.
// It first tries to match from existing tags (history + custom). If no existing
// tags are available or none match, it asks the LLM to generate new tags from
// the content — solving the cold-start problem for new users.
func AutoTagEntry(history *History, entryID, text string, customTags []string, uiLang string, autoTag, autoTitle bool) {
	if history == nil || entryID == "" || text == "" {
		return
	}

	if !autoTag && !autoTitle {
		logDebug("AutoTag: both auto-tag and auto-title disabled, skipping")
		return
	}

	resolvedUILang := resolveAutoTagUILanguage(uiLang)
	logDebug("AutoTag: entry=%s, text_len=%d, ui_lang=%s, tag=%v, title=%v", entryID, len(text), resolvedUILang, autoTag, autoTitle)

	if !IsLLMInstalled() {
		logDebug("AutoTag: local LLM not installed, skipping")
		return
	}

	endpoint, err := localLLM.Start()
	if err != nil {
		logWarn("AutoTag: failed for entry %s: %v", entryID, err)
		return
	}

	// Guard: skip if entry was deleted while LLM was starting
	if entry := history.GetByID(entryID); entry == nil || entry.DeletedAt != "" {
		logDebug("AutoTag: entry %s was deleted, skipping", entryID)
		return
	}

	var finalTags []string

	if autoTag {
		existingTags := history.Tags()

		// Merge custom tags (tags the user created but may not yet be assigned)
		// Exclude system tags that must never be auto-assigned.
		tagSet := make(map[string]bool, len(existingTags)+len(customTags))
		for _, t := range existingTags {
			if !systemTags[strings.ToLower(t)] {
				tagSet[t] = true
			}
		}
		for _, t := range customTags {
			if !systemTags[strings.ToLower(t)] {
				tagSet[t] = true
			}
		}
		allTags := make([]string, 0, len(tagSet))
		for t := range tagSet {
			allTags = append(allTags, t)
		}
		logDebug("AutoTag: %d candidate tags (from entries: %d, from custom: %d)", len(allTags), len(existingTags), len(customTags))

		if len(allTags) > 0 {
			// Try matching from existing tags first
			matchedTags, matchErr := queryLLMForTags(endpoint, text, allTags, resolvedUILang)
			if matchErr != nil {
				logWarn("AutoTag: matching failed for entry %s: %v", entryID, matchErr)
			} else {
				finalTags = matchedTags
			}
		}

		// Fallback: generate new tags if no existing tags matched (or none exist)
		if len(finalTags) == 0 {
			logDebug("AutoTag: no existing tags matched, generating new tags for entry %s", entryID)
			generatedTags, genErr := queryLLMForNewTags(endpoint, text, resolvedUILang)
			if genErr != nil {
				logWarn("AutoTag: generation failed for entry %s: %v", entryID, genErr)
			} else {
				finalTags = generatedTags
			}
		}

		if len(finalTags) == 0 {
			logDebug("AutoTag: no tags found for entry %s", entryID)
		} else {
			logDebug("AutoTag: LLM returned %d tags for entry %s", len(finalTags), entryID)
			if history.UpdateEntry(entryID, "", finalTags) {
				logInfo("AutoTag: assigned %d tags to entry %s: %v", len(finalTags), entryID, finalTags)
				NotifyHistoryChanged()
			}
		}
	}

	// Generate an AI title after tagging
	if autoTitle {
		if title := generateTitle(endpoint, text, resolvedUILang, finalTags); title != "" {
			// When auto-tag is disabled, preserve existing tags
			tagsForUpdate := finalTags
			if !autoTag {
				entry := history.GetByID(entryID)
				if entry != nil {
					tagsForUpdate = entry.Tags
				}
			}
			if history.UpdateEntry(entryID, title, tagsForUpdate) {
				logInfo("AutoTag: generated title for entry %s: %q", entryID, title)
				NotifyHistoryChanged()
			}
		}
	}
}

func autoTagPromptLanguageName(uiLang string) string {
	if languageName := promptLanguageName(uiLang); languageName != "" {
		return languageName
	}
	if languageName := promptLanguageName(GetLanguage()); languageName != "" {
		return languageName
	}
	return "English"
}

func resolveAutoTagUILanguage(uiLang string) string {
	if strings.TrimSpace(uiLang) != "" {
		return strings.TrimSpace(uiLang)
	}
	return strings.TrimSpace(GetLanguage())
}

func buildTitleSystemPrompt(uiLang string) string {
	languageRule := fmt.Sprintf("Write the title in %s.", autoTagPromptLanguageName(uiLang))
	return fmt.Sprintf(`Task: Create a short, descriptive title for a dictated note.

Rules:
- %s
- Keep the same UI language even if the note mixes languages.
- Use 3-7 words.
- Focus on the main topic, outcome, or request.
- Keep it concrete, professional, and noun-phrase-like.
- Do not start with greetings, filler, or meta-commentary.
- Do not format the answer as a list item or add labels like "Title:".
- Do not write a full sentence, question, or request.
- Do not copy imperative wording from the note.
- Do not invent people, dates, places, or facts that are not stated in the note.
- Return only the title text. No quotes, labels, or commentary.`, languageRule)
}

func buildTagClassifierSystemPrompt(availableTags []string, uiLang string) string {
	return fmt.Sprintf(
		`You are a tag classifier. Given a text and a list of tags, return which tags match the text.

TAGS: %s

Rules:
- Return a JSON array of matching tags, e.g. ["tag1", "tag2"]
- Only use tags from the list above
- A tag matches if the text is clearly about that topic
- Never translate, rewrite, or explain tags; use the exact tag text from the list
- Prefer 2-3 complementary tags when they capture distinct durable topics in the text
- Prefer reusable grouping tags over one-off details like names, greetings, or dates
- Prefer specific tags over generic ones
- Prefer tags written in %s when several tags are equally good matches
- Return at most 3 tags
- If no tag fits well, return []
- Return ONLY the JSON array

Example:
Tags: Meeting, Cooking, Travel
Text: "We discussed the project timeline and assigned tasks for next week"
Answer: ["Meeting"]`, strings.Join(availableTags, ", "), autoTagPromptLanguageName(uiLang))
}

func buildNewTagsSystemPrompt(uiLang string) string {
	return fmt.Sprintf(`You are a tag generator. Read the text and create 1-3 short tags that describe the topic.

Rules:
- Return a JSON array, e.g. ["Meeting", "Email"]
- Write all tags in %s
- Keep every tag in that UI language, even if the source text mixes languages
- Each tag must be a single Title Case word, 2-15 characters
- Tags describe WHAT the text is about (topic, not format)
- Prefer 2-3 complementary topical tags when the note clearly covers multiple themes; use 1 tag only for a single clear topic
- Favor reusable grouping tags that can organize many related notes later
- Be specific: prefer "Invoice", "Recipe", "Meeting" over generic words like "Text" or "Message"
- Avoid greetings, meta words, workflow status words, and invented specifics
- Return 1-3 tags maximum
- Return ONLY the JSON array

Example:
Text: "We need to order new office supplies and schedule a team lunch for Friday"
Answer: ["Office", "Planning"]`, autoTagPromptLanguageName(uiLang))
}

// queryLLMForTags sends the text and available tags to the local LLM,
// asking it to return only those tags that match the content.
func queryLLMForTags(llmEndpoint, text string, availableTags []string, uiLang string) ([]string, error) {
	chatURL := llmEndpoint + "/chat/completions"
	systemPrompt := buildTagClassifierSystemPrompt(availableTags, uiLang)

	// Suppress thinking mode for local Qwen models
	systemPrompt += " /no_think"

	// Truncate very long texts — classification only needs the gist
	classifyText := text
	if len(classifyText) > 2000 {
		classifyText = classifyText[:2000]
	}

	tagProfile := inference.AutoTagProfile()
	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": "TRANSCRIBED TEXT:\n" + classifyText},
		},
		"temperature": tagProfile.Temperature,
		"max_tokens":  tagProfile.MaxTokens,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	client := getAutoTagClient()
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer local")
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("LLM request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("LLM returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("empty response from LLM")
	}

	content := stripThinkBlocks(result.Choices[0].Message.Content)
	return parseTagResponse(content, availableTags)
}

// parseTagResponse extracts tags from the LLM response, validating them
// against the available tag list. Only returns tags that actually exist.
func parseTagResponse(content string, availableTags []string) ([]string, error) {
	// Build a set of valid tags (case-insensitive lookup)
	validTags := make(map[string]string, len(availableTags))
	for _, t := range availableTags {
		validTags[strings.ToLower(strings.TrimSpace(t))] = t
	}

	content = cleanTagArrayResponse(content)

	// Try JSON array parse first
	var tags []string
	if err := json.Unmarshal([]byte(content), &tags); err != nil {
		// Fallback: strip brackets and split by comma
		content = strings.Trim(content, "[]\"' \t\n\r")
		if content == "" {
			return nil, nil
		}
		parts := strings.Split(content, ",")
		tags = make([]string, 0, len(parts))
		for _, p := range parts {
			tags = append(tags, strings.Trim(p, "\"' \t"))
		}
	}

	// Validate against available tags
	matched := make([]string, 0, len(tags))
	seen := make(map[string]bool)
	for _, t := range tags {
		key := strings.ToLower(strings.TrimSpace(t))
		if original, ok := validTags[key]; ok && !seen[key] {
			matched = append(matched, original)
			seen[key] = true
		}
	}

	// Cap at 3 tags
	if len(matched) > 3 {
		matched = matched[:3]
	}

	return matched, nil
}

// queryLLMForNewTags asks the LLM to generate new tags from content.
// Used as fallback when no existing tags match or none exist yet.
func queryLLMForNewTags(llmEndpoint, text, uiLang string) ([]string, error) {
	chatURL := llmEndpoint + "/chat/completions"

	systemPrompt := buildNewTagsSystemPrompt(uiLang)

	// Suppress thinking mode for local models
	systemPrompt += " /no_think"

	classifyText := text
	if len(classifyText) > 2000 {
		classifyText = classifyText[:2000]
	}

	tagProfile := inference.AutoTagProfile()
	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": "TRANSCRIBED TEXT:\n" + classifyText},
		},
		"temperature": tagProfile.Temperature,
		"max_tokens":  tagProfile.MaxTokens,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	client := getAutoTagClient()
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer local")
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("LLM request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("LLM returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("empty response from LLM")
	}

	content := stripThinkBlocks(result.Choices[0].Message.Content)
	return parseGeneratedTags(content)
}

// parseGeneratedTags extracts and validates LLM-generated tags.
// Tags are normalized to Title Case, 2-15 characters, letters/digits/hyphens only.
// System tags (pending, duplicated) are filtered out.
func parseGeneratedTags(content string) ([]string, error) {
	content = cleanTagArrayResponse(content)

	// Parse JSON array or fall back to comma-separated
	var tags []string
	if err := json.Unmarshal([]byte(content), &tags); err != nil {
		content = strings.Trim(content, "[]\"' \t\n\r")
		if content == "" {
			return nil, nil
		}
		parts := strings.Split(content, ",")
		tags = make([]string, 0, len(parts))
		for _, p := range parts {
			tags = append(tags, strings.Trim(p, "\"' \t"))
		}
	}

	// Validate each tag
	valid := make([]string, 0, len(tags))
	seen := make(map[string]bool)
	for _, t := range tags {
		t = strings.TrimSpace(t)
		lower := strings.ToLower(t)
		if len(t) < 2 || len(t) > 15 {
			continue
		}
		if seen[lower] {
			continue
		}
		// Skip system tags
		if systemTags[lower] {
			continue
		}
		// Single word only: no spaces, only letters/digits/hyphens
		isValid := true
		for _, r := range t {
			if !(unicode.IsLetter(r) || (r >= '0' && r <= '9') || r == '-') {
				isValid = false
				break
			}
		}
		if !isValid {
			continue
		}
		// Normalize to Title Case: uppercase first letter, lowercase rest
		valid = append(valid, toTitleCase(t))
		seen[lower] = true
	}

	if len(valid) > 3 {
		valid = valid[:3]
	}

	return valid, nil
}

// toTitleCase converts a tag to Title Case (first letter uppercase, rest lowercase).
func toTitleCase(s string) string {
	if s == "" {
		return s
	}
	runes := []rune(strings.ToLower(s))
	runes[0] = unicode.ToUpper(runes[0])
	return string(runes)
}

// generateTitle asks the local LLM to create a short descriptive title for the text.
// Returns an empty string if generation fails or produces no usable result.
func generateTitle(llmEndpoint, text, lang string, topicalTags []string) string {
	title, err := queryLLMForTitle(llmEndpoint, text, lang)
	if err != nil {
		logWarn("AutoTag: title generation failed: %v", err)
		title = ""
	}
	if !titleNeedsRetry(title) {
		return title
	}
	// Single retry with tag guidance (if tags available)
	chatURL := llmEndpoint + "/chat/completions"
	input := text
	if len([]rune(input)) > 500 {
		input = string([]rune(input)[:500])
	}
	retryPrompt := buildTitleSystemPrompt(lang) + "\n- Retry rule: if your first idea is a sentence, shorten it to a compact noun-phrase title with 3-6 words."
	if len(topicalTags) > 0 {
		retryPrompt += fmt.Sprintf("\n- Main topics: %s.\n- Use these topics as guidance and return a compact title, not a sentence or request.", strings.Join(topicalTags, ", "))
	}
	retryTitle, retryErr := queryLLMForTitleWithPrompt(chatURL, input, retryPrompt)
	if retryErr == nil && !titleNeedsRetry(retryTitle) {
		return retryTitle
	}
	if fallback := fallbackTitleFromTags(topicalTags); fallback != "" {
		return fallback
	}
	return ""
}

// queryLLMForTitle sends text to the local LLM and asks for a short descriptive title.
func queryLLMForTitle(llmEndpoint, text, lang string) (string, error) {
	chatURL := llmEndpoint + "/chat/completions"

	// Truncate input to save tokens
	input := text
	if len([]rune(input)) > 500 {
		input = string([]rune(input)[:500])
	}

	return queryLLMForTitleWithPrompt(chatURL, input, buildTitleSystemPrompt(lang))
}

func queryLLMForTitleWithPrompt(chatURL, input, systemPrompt string) (string, error) {
	// Suppress thinking mode for local models
	systemPrompt += " /no_think"

	tagProfile := inference.AutoTagProfile()
	maxTokens := tagProfile.MaxTokens
	if maxTokens <= 0 || maxTokens > 24 {
		maxTokens = 24
	}
	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": "Text: " + input},
		},
		"temperature": tagProfile.Temperature,
		"max_tokens":  maxTokens,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	client := getAutoTagClient()
	req, err := http.NewRequest("POST", chatURL, bytes.NewReader(jsonData))
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer local")
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("LLM request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("LLM returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse response: %w", err)
	}
	if len(result.Choices) == 0 {
		return "", fmt.Errorf("empty response from LLM")
	}

	content := stripThinkBlocks(result.Choices[0].Message.Content)
	return cleanTitleResponse(content), nil
}

// cleanTitleResponse sanitizes the LLM title output.
func cleanTitleResponse(content string) string {
	content = strings.TrimSpace(content)

	// Strip slash commands like /no_think, /no_feedback that models may echo
	slashIdx := strings.LastIndex(content, " /")
	if slashIdx > 0 {
		after := content[slashIdx+2:]
		// Only strip if it looks like a command (single word, letters/underscore only)
		isCmd := true
		for _, r := range after {
			if r != '_' && (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') {
				isCmd = false
				break
			}
		}
		if isCmd && len(after) > 0 {
			content = strings.TrimSpace(content[:slashIdx])
		}
	}

	content = extractLastCodeFence(content)

	// Remove surrounding quotes
	content = strings.Trim(content, "\"'`")
	content = strings.TrimSpace(content)

	content = pickLikelyTitleLine(content)
	content = strings.Trim(content, "\"'`")
	content = strings.TrimSpace(content)

	// Enforce max length
	if len([]rune(content)) > 100 {
		content = string([]rune(content)[:100])
	}

	return content
}

func titleNeedsRetry(title string) bool {
	title = strings.TrimSpace(title)
	if title == "" {
		return true
	}
	if len(strings.Fields(title)) > 8 {
		return true
	}
	lower := strings.ToLower(title)
	for _, prefix := range []string{
		"hello", "hi", "hey", "hallo", "dear", "liebe", "lieber",
		"please", "bitte", "send", "sende", "schick", "schicke", "fragen", "frage",
		"ich ", "wir ",
	} {
		if lower == prefix || strings.HasPrefix(lower, prefix+" ") || strings.HasPrefix(lower, prefix+":") {
			return true
		}
	}
	if strings.HasSuffix(title, ".") || strings.HasSuffix(title, "!") || strings.HasSuffix(title, "?") {
		return true
	}
	if strings.Contains(title, ",") {
		return true
	}
	if looksLikeDayLedActionTitle(lower) {
		return true
	}
	if looksLikeTimeOnlyTitle(lower) {
		return true
	}
	return false
}

func fallbackTitleFromTags(tags []string) string {
	cleaned := make([]string, 0, len(tags))
	for _, tag := range tags {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		cleaned = append(cleaned, tag)
		if len(cleaned) == 2 {
			break
		}
	}
	switch len(cleaned) {
	case 0:
		return ""
	case 1:
		return cleaned[0]
	default:
		return cleaned[0] + " & " + cleaned[1]
	}
}

func looksLikeTimeOnlyTitle(lower string) bool {
	words := strings.Fields(lower)
	if len(words) == 0 || len(words) > 5 {
		return false
	}
	hasDigit := false
	for _, r := range lower {
		if r >= '0' && r <= '9' {
			hasDigit = true
			break
		}
	}
	if !hasDigit {
		return false
	}
	for _, marker := range []string{
		"montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag",
		"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
		"uhr",
	} {
		if strings.Contains(lower, marker) {
			return true
		}
	}
	// "am"/"pm" only count when adjacent to a digit (avoid false positive on German "am")
	if timeAdjacentRe.MatchString(lower) {
		return true
	}
	return false
}

func looksLikeDayLedActionTitle(lower string) bool {
	parts := strings.SplitN(lower, ":", 2)
	if len(parts) != 2 {
		return false
	}
	prefix := strings.TrimSpace(parts[0])
	suffix := strings.TrimSpace(parts[1])
	if prefix == "" || suffix == "" {
		return false
	}
	isDay := false
	for _, day := range []string{
		"montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag",
		"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
	} {
		if prefix == day {
			isDay = true
			break
		}
	}
	if !isDay {
		return false
	}
	for _, marker := range []string{" koordinier", " prüfen", " pruefen", " senden", " schick", " vorbereit", " planen", " finalis"} {
		if strings.Contains(" "+suffix, marker) {
			return true
		}
	}
	return len(strings.Fields(suffix)) >= 2
}

func cleanTagArrayResponse(content string) string {
	content = extractLastCodeFence(strings.TrimSpace(content))
	if candidate := extractLastJSONArray(content); candidate != "" {
		content = candidate
	}
	return strings.TrimSpace(content)
}

func extractLastCodeFence(content string) string {
	content = strings.TrimSpace(content)
	if idx := strings.LastIndex(content, "```"); idx > 0 {
		before := content[:idx]
		if open := strings.LastIndex(before, "```"); open >= 0 {
			inner := before[open+3:]
			if nl := strings.IndexByte(inner, '\n'); nl >= 0 {
				inner = inner[nl+1:]
			} else {
				inner = strings.TrimSpace(inner)
			}
			content = strings.TrimSpace(inner)
		}
	}
	return strings.TrimSpace(content)
}

func pickLikelyTitleLine(content string) string {
	lines := strings.Split(content, "\n")
	for idx, line := range lines {
		line = strings.TrimSpace(strings.Trim(line, "\"'`"))
		if line == "" {
			continue
		}
		if cleaned, ok := stripTitleMetaPrefix(line); ok {
			line = cleaned
		}
		line = stripListMarker(line)
		if line == "" {
			continue
		}
		if idx < len(lines)-1 && isTitlePrefaceLine(line) {
			continue
		}
		return line
	}
	return ""
}

func stripTitleMetaPrefix(line string) (string, bool) {
	colon := strings.IndexByte(line, ':')
	if colon <= 0 {
		return line, false
	}
	prefix := strings.ToLower(strings.TrimSpace(line[:colon]))
	if !isTitleMetaPrefix(prefix) {
		return line, false
	}
	return strings.TrimSpace(line[colon+1:]), true
}

func isTitlePrefaceLine(line string) bool {
	lower := strings.ToLower(strings.TrimSpace(line))
	switch lower {
	case "hi", "hi!", "hello", "hello!", "hey", "hey!", "hallo", "hallo!":
		return true
	}
	if strings.HasSuffix(lower, ":") {
		return isTitleMetaPrefix(strings.TrimSuffix(lower, ":"))
	}
	return false
}

func isTitleMetaPrefix(prefix string) bool {
	prefix = strings.TrimSpace(prefix)
	switch prefix {
	case "title", "suggested title", "possible title", "short title", "concise title", "titel", "vorgeschlagener titel", "kurzer titel", "subject", "betreff", "headline", "überschrift":
		return true
	}
	for _, candidate := range []string{"here is the title", "here's the title", "here is a title", "here's a title", "hier ist der titel"} {
		if prefix == candidate {
			return true
		}
	}
	return false
}

func stripListMarker(line string) string {
	line = strings.TrimSpace(line)
	for _, prefix := range []string{"- ", "* ", "• "} {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix))
		}
	}
	return line
}

func extractLastJSONArray(content string) string {
	for start := strings.LastIndexByte(content, '['); start >= 0; {
		rest := content[start:]
		offset := strings.IndexByte(rest, ']')
		for offset >= 0 {
			candidate := strings.TrimSpace(rest[:offset+1])
			var tags []string
			if err := json.Unmarshal([]byte(candidate), &tags); err == nil {
				return candidate
			}
			next := strings.IndexByte(rest[offset+1:], ']')
			if next < 0 {
				break
			}
			offset += next + 1
		}
		if start == 0 {
			break
		}
		start = strings.LastIndexByte(content[:start], '[')
	}
	return ""
}
