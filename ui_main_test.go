package main

import (
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// TestJSSyntax validates that all embedded JS files parse without errors.
// This catches duplicate declarations, syntax errors, and other issues
// that would silently crash the entire WebView2 UI at runtime.
func TestJSSyntax(t *testing.T) {
	if _, err := exec.LookPath("node"); err != nil {
		t.Skip("node not in PATH")
	}

	err := fs.WalkDir(uiMainFS, "ui_main/scripts", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".js") {
			return err
		}
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, path)
			if err != nil {
				t.Fatalf("Failed to read %s: %v", path, err)
			}
			tmpDir := t.TempDir()
			tmpFile := filepath.Join(tmpDir, filepath.Base(path))
			if err := os.WriteFile(tmpFile, data, 0644); err != nil {
				t.Fatalf("Failed to write temp file: %v", err)
			}
			cmd := exec.Command("node", "-c", tmpFile)
			output, err := cmd.CombinedOutput()
			if err != nil {
				t.Errorf("JS syntax error in %s:\n%s", path, string(output))
			}
		})
		return nil
	})
	if err != nil {
		t.Fatalf("Failed to walk embedded JS files: %v", err)
	}
}

// TestCSSNotEmpty validates that all embedded CSS files are not empty and
// contain no obvious syntax issues (unclosed braces).
func TestCSSNotEmpty(t *testing.T) {
	err := fs.WalkDir(uiMainFS, "ui_main/styles", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".css") {
			return err
		}
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, path)
			if err != nil {
				t.Fatalf("Failed to read %s: %v", path, err)
			}
			content := string(data)
			if len(strings.TrimSpace(content)) == 0 {
				t.Errorf("CSS file %s is empty", path)
			}
			opens := strings.Count(content, "{")
			closes := strings.Count(content, "}")
			if opens != closes {
				t.Errorf("CSS file %s has unbalanced braces: %d opens, %d closes", path, opens, closes)
			}
		})
		return nil
	})
	if err != nil {
		t.Fatalf("Failed to walk embedded CSS files: %v", err)
	}
}

// TestJSConcatenatedSyntax validates that ALL JS files concatenated together
// (as they are loaded in the WebView) don't have conflicting declarations.
// This is the exact scenario that caused the isSystemTag duplicate crash.
func TestJSConcatenatedSyntax(t *testing.T) {
	if _, err := exec.LookPath("node"); err != nil {
		t.Skip("node not in PATH")
	}

	combined := collectEmbeddedFiles(uiMainFS, "ui_main/scripts", ".js")
	if len(combined) == 0 {
		t.Fatal("No JS files found")
	}

	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "combined.js")
	if err := os.WriteFile(tmpFile, []byte(combined), 0644); err != nil {
		t.Fatalf("Failed to write combined JS: %v", err)
	}

	cmd := exec.Command("node", "-c", tmpFile)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Errorf("Combined JS syntax error (duplicate declarations?):\n%s", string(output))
	}
}

// TestHTMLTemplateValid validates the HTML template has the required placeholders
// replaced and produces valid HTML when styles/scripts are injected.
func TestHTMLTemplateValid(t *testing.T) {
	html := assembleMainHTML()
	if len(html) < 100 {
		t.Fatal("HTML output too short, likely a build error")
	}
	if strings.Contains(html, "/* {{STYLES}} */") {
		t.Error("CSS placeholder was not replaced")
	}
	if strings.Contains(html, "/* {{SCRIPTS}} */") {
		t.Error("JS placeholder was not replaced")
	}
	if strings.Contains(html, "<!-- {{PAGES}} -->") {
		t.Error("Pages placeholder was not replaced")
	}
	if !strings.Contains(html, "page-history") {
		t.Error("Missing history page content after assembly")
	}
	if !strings.Contains(html, "<html") {
		t.Error("Missing <html> tag")
	}
	if !strings.Contains(html, "</html>") {
		t.Error("Missing </html> closing tag")
	}
}

func TestSettingsCloudTranscriptionLayout(t *testing.T) {
	html := assembleMainHTML()
	if !strings.Contains(html, `id="select-cloud-stt-provider"`) {
		t.Fatal("missing cloud transcription provider selector")
	}
	if !strings.Contains(html, `id="cloud-stt-openai-key-row"`) {
		t.Fatal("missing OpenAI transcription key row")
	}
	if !strings.Contains(html, `id="cloud-llm-openai-key-row"`) {
		t.Fatal("missing OpenAI Smart Mode key row")
	}
	if !strings.Contains(html, `id="cloud-llm-groq-key-row"`) {
		t.Fatal("missing Groq Smart Mode key row")
	}
	if strings.Contains(html, `id="cloud-stt-openai-hint"`) {
		t.Fatal("stale separate OpenAI hint block should not remain in settings layout")
	}
}

// ─── HTML / CSS Lint Tests ─────────────────────────────────────────

// voidElements are self-closing HTML tags that never have a closing tag.
var voidElements = map[string]bool{
	"area": true, "base": true, "br": true, "col": true, "embed": true,
	"hr": true, "img": true, "input": true, "link": true, "meta": true,
	"param": true, "source": true, "track": true, "wbr": true,
}

// reTagOpen matches <tagname ... > (not self-closing, not void)
var reTagOpen = regexp.MustCompile(`<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*/?>`)

// reTagClose matches </tagname>
var reTagClose = regexp.MustCompile(`</([a-zA-Z][a-zA-Z0-9]*)\s*>`)

// countHTMLTags counts opening and closing tags (excluding void/self-closing)
// for common container elements that cause nesting bugs when unclosed.
func countHTMLTags(content string) map[string][2]int {
	tags := map[string][2]int{}
	for _, m := range reTagOpen.FindAllStringSubmatch(content, -1) {
		tag := strings.ToLower(m[0])
		name := strings.ToLower(m[1])
		if voidElements[name] {
			continue
		}
		if strings.HasSuffix(strings.TrimSpace(tag), "/>") {
			continue
		}
		v := tags[name]
		v[0]++
		tags[name] = v
	}
	for _, m := range reTagClose.FindAllStringSubmatch(content, -1) {
		name := strings.ToLower(m[1])
		v := tags[name]
		v[1]++
		tags[name] = v
	}
	return tags
}

// TestHTMLPageTagBalance validates that every page HTML file has balanced
// opening/closing tags for container elements (div, span, section, etc.).
// This prevents the exact bug where an unclosed <div> in one page causes
// all subsequent pages to be nested inside it, making them invisible.
func TestHTMLPageTagBalance(t *testing.T) {
	criticalTags := []string{"div", "section", "main", "aside", "nav", "header", "footer", "article", "ul", "ol", "table", "thead", "tbody", "tr"}

	err := fs.WalkDir(uiMainFS, "ui_main/pages", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".html") {
			return err
		}
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, path)
			if err != nil {
				t.Fatalf("Failed to read %s: %v", path, err)
			}
			content := string(data)
			tags := countHTMLTags(content)
			for _, tag := range criticalTags {
				counts, ok := tags[tag]
				if !ok {
					continue
				}
				if counts[0] != counts[1] {
					t.Errorf("<%s> tag imbalance: %d opens, %d closes (diff: %+d)",
						tag, counts[0], counts[1], counts[0]-counts[1])
				}
			}
		})
		return nil
	})
	if err != nil {
		t.Fatalf("Failed to walk page files: %v", err)
	}
}

// TestHTMLPagesNotNested verifies that page-* divs in the assembled HTML
// are siblings, not nested inside each other. When one page's unclosed tag
// swallows the next page, switchPage() breaks because hiding the parent
// hides all children.
func TestHTMLPagesNotNested(t *testing.T) {
	html := assembleMainHTML()

	rePageDiv := regexp.MustCompile(`<div[^>]+id="page-([a-z]+)"`)
	matches := rePageDiv.FindAllStringIndex(html, -1)
	if len(matches) < 3 {
		t.Fatalf("Expected at least 3 page divs, found %d", len(matches))
	}

	type pageInfo struct {
		name  string
		depth int
	}
	var pages []pageInfo

	reOpen := regexp.MustCompile(`<div[\s>]`)
	reCloseDiv := regexp.MustCompile(`</div>`)

	for _, m := range matches {
		pos := m[0]
		prefix := html[:pos]
		opens := len(reOpen.FindAllString(prefix, -1))
		closes := len(reCloseDiv.FindAllString(prefix, -1))
		depth := opens - closes

		nameMatch := rePageDiv.FindStringSubmatch(html[pos:])
		name := "unknown"
		if len(nameMatch) > 1 {
			name = nameMatch[1]
		}
		pages = append(pages, pageInfo{name: name, depth: depth})
	}

	expectedDepth := pages[0].depth
	for _, p := range pages[1:] {
		if p.depth != expectedDepth {
			t.Errorf("page-%s at div depth %d, expected %d (same as page-%s) — likely unclosed tag in preceding page",
				p.name, p.depth, expectedDepth, pages[0].name)
		}
	}
}

// TestHTMLAssembledTagBalance validates the fully assembled HTML has balanced
// container tags across the entire document (excluding script blocks, which
// may contain HTML template strings that create false positives).
func TestHTMLAssembledTagBalance(t *testing.T) {
	html := assembleMainHTML()

	// Strip <script>...</script> blocks — they contain JS template literals
	// with HTML-like content that confuses tag counting.
	reScript := regexp.MustCompile(`(?s)<script[^>]*>.*?</script>`)
	htmlNoScript := reScript.ReplaceAllString(html, "")

	criticalTags := []string{"div", "section", "main", "aside", "nav", "header", "footer"}
	tags := countHTMLTags(htmlNoScript)

	for _, tag := range criticalTags {
		counts, ok := tags[tag]
		if !ok {
			continue
		}
		if counts[0] != counts[1] {
			t.Errorf("Assembled HTML: <%s> imbalance: %d opens, %d closes (diff: %+d)",
				tag, counts[0], counts[1], counts[0]-counts[1])
		}
	}
}

// TestCSSValidation performs structural validation on CSS files:
// unclosed comments, unbalanced parentheses, stray characters.
func TestCSSValidation(t *testing.T) {
	err := fs.WalkDir(uiMainFS, "ui_main/styles", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".css") {
			return err
		}
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, path)
			if err != nil {
				t.Fatalf("Failed to read %s: %v", path, err)
			}
			content := string(data)

			// Check unclosed comments
			commentOpens := strings.Count(content, "/*")
			commentCloses := strings.Count(content, "*/")
			if commentOpens != commentCloses {
				t.Errorf("Unclosed CSS comment: %d /* vs %d */", commentOpens, commentCloses)
			}

			// Strip comments for further checks
			reComment := regexp.MustCompile(`/\*[\s\S]*?\*/`)
			stripped := reComment.ReplaceAllString(content, "")

			// Check brace balance (enhanced version of TestCSSNotEmpty)
			braceOpens := strings.Count(stripped, "{")
			braceCloses := strings.Count(stripped, "}")
			if braceOpens != braceCloses {
				t.Errorf("Unbalanced braces: %d { vs %d }", braceOpens, braceCloses)
			}

			// Check parenthesis balance (var(), calc(), etc.)
			parenOpens := strings.Count(stripped, "(")
			parenCloses := strings.Count(stripped, ")")
			if parenOpens != parenCloses {
				t.Errorf("Unbalanced parentheses: %d ( vs %d )", parenOpens, parenCloses)
			}

			// Check for stray top-level semicolons
			lines := strings.Split(stripped, "\n")
			for i, line := range lines {
				trimmed := strings.TrimSpace(line)
				if trimmed == ";" {
					t.Errorf("Line %d: stray semicolon outside rule block", i+1)
				}
				if trimmed == "}}" {
					t.Errorf("Line %d: double closing brace '}}' — likely a typo", i+1)
				}
			}
		})
		return nil
	})
	if err != nil {
		t.Fatalf("Failed to walk CSS files: %v", err)
	}
}

// TestHTMLTemplateTagBalance validates template.html has balanced tags.
func TestHTMLTemplateTagBalance(t *testing.T) {
	data, err := fs.ReadFile(uiMainFS, "ui_main/template.html")
	if err != nil {
		t.Fatalf("Failed to read template: %v", err)
	}
	content := string(data)

	// Filter out injection placeholder lines
	var filtered []string
	for _, line := range strings.Split(content, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.Contains(trimmed, "{{PAGES}}") ||
			strings.Contains(trimmed, "{{STYLES}}") ||
			strings.Contains(trimmed, "{{SCRIPTS}}") {
			continue
		}
		filtered = append(filtered, line)
	}
	filteredContent := strings.Join(filtered, "\n")
	tags := countHTMLTags(filteredContent)

	for tag, counts := range tags {
		if voidElements[tag] {
			continue
		}
		if counts[0] != counts[1] {
			t.Errorf("template.html: <%s> imbalance: %d opens, %d closes", tag, counts[0], counts[1])
		}
	}
}

// TestHTMLComponentBalance validates component templates have balanced tags.
func TestHTMLComponentBalance(t *testing.T) {
	components, err := fs.ReadDir(uiMainFS, "ui_main/components")
	if err != nil {
		t.Skip("No components directory")
		return
	}
	reGoTmpl := regexp.MustCompile(`\{\{[^}]*\}\}`)
	for _, d := range components {
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".html") {
			continue
		}
		t.Run(d.Name(), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, "ui_main/components/"+d.Name())
			if err != nil {
				t.Fatalf("Failed to read %s: %v", d.Name(), err)
			}
			cleaned := reGoTmpl.ReplaceAllString(string(data), "")
			tags := countHTMLTags(cleaned)
			for tag, counts := range tags {
				if voidElements[tag] {
					continue
				}
				if counts[0] != counts[1] {
					t.Errorf("<%s> imbalance: %d opens, %d closes", tag, counts[0], counts[1])
				}
			}
		})
	}
}

// TestHTMLPageHasRequiredStructure validates each page file contains a proper
// page container div and ends with a closing tag.
func TestHTMLPageHasRequiredStructure(t *testing.T) {
	rePageStart := regexp.MustCompile(`<div[^>]*\bclass="[^"]*\bpage\b[^"]*"[^>]*\bid="page-[a-z]+"`)
	rePageStartAlt := regexp.MustCompile(`<div[^>]*\bid="page-[a-z]+"[^>]*\bclass="[^"]*\bpage\b`)

	err := fs.WalkDir(uiMainFS, "ui_main/pages", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".html") {
			return err
		}
		t.Run(filepath.Base(path), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, path)
			if err != nil {
				t.Fatalf("Failed to read %s: %v", path, err)
			}
			content := string(data)
			if !rePageStart.MatchString(content) && !rePageStartAlt.MatchString(content) {
				t.Error("Page file must contain a <div> with class=\"page\" and id=\"page-*\"")
			}
			lines := strings.Split(strings.TrimSpace(content), "\n")
			lastLine := strings.TrimSpace(lines[len(lines)-1])
			if lastLine != "</div>" {
				t.Errorf("Page file should end with </div>, got: %q", lastLine)
			}
		})
		return nil
	})
	if err != nil {
		t.Fatalf("Failed to walk page files: %v", err)
	}
}

// TestLintSummary ensures the lint suite covers all expected files.
func TestLintSummary(t *testing.T) {
	var htmlCount, cssCount, jsCount int
	_ = fs.WalkDir(uiMainFS, "ui_main", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		switch {
		case strings.HasSuffix(path, ".html"):
			htmlCount++
		case strings.HasSuffix(path, ".css"):
			cssCount++
		case strings.HasSuffix(path, ".js"):
			jsCount++
		}
		return nil
	})
	t.Logf("Lint coverage: %d HTML, %d CSS, %d JS files", htmlCount, cssCount, jsCount)
	if htmlCount < 7 {
		t.Errorf("Expected at least 7 HTML files, found %d", htmlCount)
	}
}

// TestJSTemplateDivBalance checks that HTML template literals in JS files
// have balanced <div> opening and closing tags. This catches bugs where
// dynamically rendered HTML (e.g., _renderEntryCard) has unclosed divs
// that would cause entries to merge or pages to nest incorrectly.
func TestJSTemplateDivBalance(t *testing.T) {
	entries, err := fs.ReadDir(uiMainFS, "ui_main/scripts")
	if err != nil {
		t.Fatalf("Failed to read JS scripts: %v", err)
	}

	templateRe := regexp.MustCompile("(?s)`([^`]*)`")
	divOpenRe := regexp.MustCompile(`<div[\s>]`)
	divCloseRe := regexp.MustCompile(`</div>`)

	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".js") {
			continue
		}
		t.Run(e.Name(), func(t *testing.T) {
			data, err := fs.ReadFile(uiMainFS, "ui_main/scripts/"+e.Name())
			if err != nil {
				t.Fatalf("Read error: %v", err)
			}
			content := string(data)
			matches := templateRe.FindAllString(content, -1)
			totalOpens := 0
			totalCloses := 0
			for _, m := range matches {
				opens := len(divOpenRe.FindAllString(m, -1))
				closes := len(divCloseRe.FindAllString(m, -1))
				totalOpens += opens
				totalCloses += closes
			}
			if totalOpens != totalCloses {
				t.Errorf("%s: JS template literals have %d <div> opens vs %d </div> closes (diff: %d)",
					e.Name(), totalOpens, totalCloses, totalOpens-totalCloses)
			}
		})
	}
}

// Ensure fmt import is used
var _ = fmt.Sprintf