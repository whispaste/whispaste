package main

import (
	"strings"
	"testing"
	"text/template"
)

func TestParseComponentAttrs(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantKeys map[string]string
	}{
		{
			name:  "key-value pairs",
			input: ` id="autopaste" label="labelAutoPaste"`,
			wantKeys: map[string]string{
				"id":    "autopaste",
				"label": "labelAutoPaste",
			},
		},
		{
			name:  "boolean flag",
			input: ` id="test" checked`,
			wantKeys: map[string]string{
				"id":      "test",
				"checked": "true",
			},
		},
		{
			name:  "mixed attributes",
			input: ` id="sm" label="lbl" labelDefault="Text" checked onchange="fn()"`,
			wantKeys: map[string]string{
				"id":           "sm",
				"label":        "lbl",
				"labelDefault": "Text",
				"checked":      "true",
				"onchange":     "fn()",
			},
		},
		{
			name:     "empty",
			input:    "",
			wantKeys: map[string]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseComponentAttrs(tt.input)
			for k, v := range tt.wantKeys {
				if got[k] != v {
					t.Errorf("key %q: got %q, want %q", k, got[k], v)
				}
			}
			if len(got) != len(tt.wantKeys) {
				t.Errorf("got %d keys, want %d: %v", len(got), len(tt.wantKeys), got)
			}
		})
	}
}

func TestExpandComponents(t *testing.T) {
	tmpl, err := template.New("test-comp").Option("missingkey=zero").Parse(
		`<div id="{{.id}}">{{.text}}</div>`)
	if err != nil {
		t.Fatal(err)
	}
	components := map[string]*template.Template{"test-comp": tmpl}

	input := `<p>before</p>
<!-- @test-comp id="abc" text="hello" -->
<p>after</p>`

	got := expandComponents(input, components)

	if !strings.Contains(got, `<div id="abc">hello</div>`) {
		t.Errorf("component not expanded correctly:\n%s", got)
	}
	if strings.Contains(got, "<!-- @test-comp") {
		t.Error("marker was not replaced")
	}
	if !strings.Contains(got, "<p>before</p>") || !strings.Contains(got, "<p>after</p>") {
		t.Error("surrounding content was damaged")
	}
}

func TestExpandComponentsBooleanFlag(t *testing.T) {
	tmpl, err := template.New("flag-comp").Option("missingkey=zero").Parse(
		`<input{{if .checked}} checked{{end}}>`)
	if err != nil {
		t.Fatal(err)
	}
	components := map[string]*template.Template{"flag-comp": tmpl}

	withFlag := expandComponents(`<!-- @flag-comp checked -->`, components)
	if !strings.Contains(withFlag, "checked") {
		t.Error("boolean flag not expanded")
	}

	withoutFlag := expandComponents(`<!-- @flag-comp -->`, components)
	if strings.Contains(withoutFlag, "checked") {
		t.Error("absent flag should not produce 'checked'")
	}
}

func TestExpandComponentsUnknownPreserved(t *testing.T) {
	components := map[string]*template.Template{}
	input := `<!-- @unknown-comp id="x" -->`
	got := expandComponents(input, components)
	if got != input {
		t.Errorf("unknown component marker should be preserved, got: %s", got)
	}
}

func TestComponentsIntegration(t *testing.T) {
	// Verify assembleMainHTML still works with component expansion
	html := assembleMainHTML()
	if strings.Contains(html, "<!-- @toggle-row") {
		t.Error("toggle-row markers were not expanded in assembled HTML")
	}
	if strings.Contains(html, "<!-- @page-header") {
		t.Error("page-header markers were not expanded in assembled HTML")
	}
	// Verify expanded content exists
	if !strings.Contains(html, `id="toggle-autopaste"`) {
		t.Error("toggle-autopaste not found after component expansion")
	}
	if !strings.Contains(html, `id="toggle-smartmode"`) {
		t.Error("toggle-smartmode not found after component expansion")
	}
}
