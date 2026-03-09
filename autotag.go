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
// It retrieves all known tags, asks the LLM which ones match the text, and
// updates the entry with the matching tags. Only existing tags are assigned —
// no new tags are created. Runs asynchronously and fails silently.
func AutoTagEntry(history *History, entryID, text string) {
	if history == nil || entryID == "" || text == "" {
		return
	}

	existingTags := history.Tags()
	if len(existingTags) == 0 {
		logDebug("AutoTag: no existing tags, skipping")
		return
	}

	if !IsLLMInstalled() {
		logDebug("AutoTag: local LLM not installed, skipping")
		return
	}

	endpoint, err := localLLM.Start()
	if err != nil {
		logWarn("AutoTag: failed to start local LLM: %v", err)
		return
	}

	matchedTags, err := queryLLMForTags(endpoint, text, existingTags)
	if err != nil {
		logWarn("AutoTag: LLM query failed: %v", err)
		return
	}

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
		`You are a tag classifier. Given a text and a list of available tags, return ONLY the tags that are relevant to the text content. Rules:
- Return tags as a JSON array of strings, e.g. ["tag1", "tag2"]
- Only use tags from the provided list — never invent new tags
- Select 1–3 tags maximum
- If no tags match, return an empty array []
- Return ONLY the JSON array, no explanation

Available tags: %s`, tagList)

	reqBody := map[string]interface{}{
		"model": "local",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": text},
		},
		"temperature": 0.1,
		"max_tokens":  256,
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

	// Cap at 3 tags
	if len(matched) > 3 {
		matched = matched[:3]
	}

	return matched, nil
}
