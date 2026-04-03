package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/whispaste/whispaste/internal/inference"
)

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

	logDebug("AutoTag: entry=%s, text_len=%d, tag=%v, title=%v", entryID, len(text), autoTag, autoTitle)

	if !IsLLMInstalled() {
		logDebug("AutoTag: local LLM not installed, skipping")
		return
	}

	endpoint, err := localLLM.Start()
	if err != nil {
		logWarn("AutoTag: failed for entry %s: %v", entryID, err)
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
			matchedTags, matchErr := queryLLMForTags(endpoint, text, allTags)
			if matchErr != nil {
				logWarn("AutoTag: matching failed for entry %s: %v", entryID, matchErr)
			} else {
				finalTags = matchedTags
			}
		}

		// Fallback: generate new tags if no existing tags matched (or none exist)
		if len(finalTags) == 0 {
			logDebug("AutoTag: no existing tags matched, generating new tags for entry %s", entryID)
			generatedTags, genErr := queryLLMForNewTags(endpoint, text)
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
		if title := generateTitle(endpoint, text, uiLang); title != "" {
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

// queryLLMForTags sends the text and available tags to the local LLM,
// asking it to return only those tags that match the content.
func queryLLMForTags(llmEndpoint, text string, availableTags []string) ([]string, error) {
	chatURL := llmEndpoint + "/chat/completions"
	tagList := strings.Join(availableTags, ", ")

	systemPrompt := fmt.Sprintf(
		`You are a tag classifier. Given a text and a list of tags, return which tags match the text.

TAGS: %s

Rules:
- Return a JSON array of matching tags, e.g. ["tag1", "tag2"]
- Only use tags from the list above
- A tag matches if the text is clearly about that topic
- Prefer specific tags over generic ones
- Return at most 3 tags
- If no tag fits well, return []
- Return ONLY the JSON array

Example:
Tags: Meeting, Cooking, Travel
Text: "We discussed the project timeline and assigned tasks for next week"
Answer: ["Meeting"]`, tagList)

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

	// Strip markdown code fences that small models often emit.
	// Extract the LAST fenced block (most likely the actual answer).
	content = strings.TrimSpace(content)
	if idx := strings.LastIndex(content, "```"); idx > 0 {
		// Find the opening fence that pairs with this closing fence
		before := content[:idx]
		if open := strings.LastIndex(before, "```"); open >= 0 {
			inner := before[open+3:]
			// Skip optional language tag on opening fence
			if nl := strings.IndexByte(inner, '\n'); nl >= 0 {
				inner = inner[nl+1:]
			} else {
				inner = strings.TrimSpace(inner)
			}
			content = strings.TrimSpace(inner)
		}
	}

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
func queryLLMForNewTags(llmEndpoint, text string) ([]string, error) {
	chatURL := llmEndpoint + "/chat/completions"

	systemPrompt := `You are a tag generator. Read the text and create 1-3 short tags that describe the topic.

Rules:
- Return a JSON array, e.g. ["Meeting", "Email"]
- Each tag must be a single Title Case word, 2-15 characters
- Tags describe WHAT the text is about (topic, not format)
- Be specific: prefer "Invoice", "Recipe", "Meeting" over generic words like "Text" or "Message"
- Return 1-3 tags maximum
- Return ONLY the JSON array

Example:
Text: "We need to order new office supplies and schedule a team lunch for Friday"
Answer: ["Office", "Planning"]`

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
	content = strings.TrimSpace(content)

	// Strip markdown code fences
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
func generateTitle(llmEndpoint, text, lang string) string {
	title, err := queryLLMForTitle(llmEndpoint, text, lang)
	if err != nil {
		logWarn("AutoTag: title generation failed: %v", err)
		return ""
	}
	return title
}

// queryLLMForTitle sends text to the local LLM and asks for a short descriptive title.
func queryLLMForTitle(llmEndpoint, text, lang string) (string, error) {
	chatURL := llmEndpoint + "/chat/completions"

	// Truncate input to save tokens
	input := text
	if len([]rune(input)) > 500 {
		input = string([]rune(input)[:500])
	}

	// Resolve language name for the prompt
	langName := "English"
	switch strings.ToLower(lang) {
	case "de":
		langName = "German"
	case "en":
		langName = "English"
	}

	systemPrompt := fmt.Sprintf(`You generate descriptive titles for voice recordings. Rules:
1. LANGUAGE: You MUST write the title in %s. This is mandatory — no exceptions.
2. LENGTH: 5-10 words, descriptive and specific to the content.
3. OUTPUT: Return ONLY the title text. No quotes, no labels, no explanation, no commands.

German title examples:
Text: "Wir haben den Projektzeitplan besprochen und Aufgaben für nächste Woche verteilt"
Projektplanung und Aufgabenverteilung für nächste Woche

Text: "Das Dashboard sieht optisch nicht gut aus, die Titel sind zu kurz"
Feedback zum Dashboard-Design und Titeldarstellung

English title examples:
Text: "We discussed the project timeline and assigned tasks for next week"
Weekly Project Planning and Task Assignment

Text: "The overlay has a green blinking bar that looks confusing"
Overlay Visual Feedback and Green Bar Issue`, langName)

	// Suppress thinking mode for local models
	systemPrompt += " /no_think"

	tagProfile := inference.AutoTagProfile()
	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": "Text: " + input},
		},
		"temperature": tagProfile.Temperature,
		"max_tokens":  tagProfile.MaxTokens,
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

	// Strip markdown code fences
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

	// Remove surrounding quotes
	content = strings.Trim(content, "\"'`")
	content = strings.TrimSpace(content)

	// Take only the first line
	if nl := strings.IndexByte(content, '\n'); nl >= 0 {
		content = strings.TrimSpace(content[:nl])
	}

	// Enforce max length
	if len([]rune(content)) > 100 {
		content = string([]rune(content)[:100])
	}

	return content
}
