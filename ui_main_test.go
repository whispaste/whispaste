package main

import (
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
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
	if !strings.Contains(html, "<html") {
		t.Error("Missing <html> tag")
	}
	if !strings.Contains(html, "</html>") {
		t.Error("Missing </html> closing tag")
	}
}
