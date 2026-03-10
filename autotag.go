package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// AutoTagEntry uses the local LLM to assign existing tags to a history entry.
// It retrieves all known tags (both from history and custom config tags), asks
// the LLM which ones match the text, and updates the entry with the matching
// tags. Only known tags are assigned — no new tags are created.
func AutoTagEntry(history *History, entryID, text string, customTags []string) {
	if history == nil || entryID == "" || text == "" {
		return
	}
	logDebug("AutoTag: entry=%s, text_len=%d", entryID, len(text))

	existingTags := history.Tags()

	// Merge custom tags (tags the user created but may not yet be assigned)
	tagSet := make(map[string]bool, len(existingTags)+len(customTags))
	for _, t := range existingTags {
		tagSet[t] = true
	}
	for _, t := range customTags {
		tagSet[t] = true
	}
	allTags := make([]string, 0, len(tagSet))
	for t := range tagSet {
		allTags = append(allTags, t)
	}
	logDebug("AutoTag: %d candidate tags (from entries: %d, from custom: %d)", len(allTags), len(existingTags), len(customTags))

	if len(allTags) == 0 {
		logDebug("AutoTag: no candidate tags, skipping")
		return
	}

	if !IsLLMInstalled() {
		logDebug("AutoTag: local LLM not installed, skipping")
		return
	}

	endpoint, err := localLLM.Start()
	if err != nil {
		logWarn("AutoTag: failed for entry %s: %v", entryID, err)
		return
	}

	matchedTags, err := queryLLMForTags(endpoint, text, allTags)
	if err != nil {
		logWarn("AutoTag: failed for entry %s: %v", entryID, err)
		return
	}
	logDebug("AutoTag: LLM returned %d tags for entry %s", len(matchedTags), entryID)

	if len(matchedTags) == 0 {
		logDebug("AutoTag: no matching tags found for entry %s", entryID)
		return
	}

	if history.UpdateEntry(entryID, "", matchedTags) {
		logInfo("AutoTag: assigned %d tags to entry %s: %v", len(matchedTags), entryID, matchedTags)
		NotifyHistoryChanged()
	}
}

// queryLLMForTags sends the text and available tags to the local LLM,
// asking it to return only those tags that match the content.
func queryLLMForTags(llmEndpoint, text string, availableTags []string) ([]string, error) {
	chatURL := llmEndpoint + "/chat/completions"
	tagList := strings.Join(availableTags, ", ")

	systemPrompt := fmt.Sprintf(
		`Classify transcribed speech by assigning tags from a fixed list. Precision is critical — a wrong tag is worse than no tag.

RULES:
1. Return a JSON array, e.g. ["tag1"] or ["tag1", "tag2"]
2. ONLY use tags from the AVAILABLE TAGS list below — never invent new ones
3. A tag must match the MAIN TOPIC of the text, not just a passing mention
4. If you are unsure whether a tag fits → leave it out
5. If no tag clearly fits → return []
6. Maximum 2 tags, only if the text genuinely covers two distinct topics
7. Return ONLY the JSON array, nothing else

WHAT COUNTS AS A MATCH:
- The text is primarily about that tag's topic
- The tag describes the core subject or purpose of the text

WHAT DOES NOT COUNT:
- A word related to the tag appears once briefly
- The tag is only loosely or vaguely associated
- You are guessing

AVAILABLE TAGS: %s`, tagList)

	// Truncate very long texts — classification only needs the gist
	classifyText := text
	if len(classifyText) > 2000 {
		classifyText = classifyText[:2000]
	}

	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": "TRANSCRIBED TEXT:\n" + classifyText},
		},
		"temperature": 0.0,
		"max_tokens":  64,
	}

	jsonData, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	client := &http.Client{Timeout: 30 * time.Second}
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

	content := strings.TrimSpace(result.Choices[0].Message.Content)
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

	// Cap at 2 tags — stricter to avoid false positives with local models
	if len(matched) > 2 {
		matched = matched[:2]
	}

	return matched, nil
}
