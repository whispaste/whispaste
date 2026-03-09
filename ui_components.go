package main

import (
	"embed"
	"io/fs"
	"regexp"
	"strings"
	"text/template"
)

// componentMarkerRE matches self-closing component markers: <!-- @name key="value" flag -->
var componentMarkerRE = regexp.MustCompile(`<!--\s*@([a-zA-Z][\w-]*)((?:\s+\w[\w-]*(?:="[^"]*")?)*)\s*-->`)

// componentAttrRE matches key="value" pairs inside a marker.
var componentAttrRE = regexp.MustCompile(`(\w[\w-]*)="([^"]*)"`)

// loadComponentTemplates reads .html files from ui_main/components/ and parses
// them as Go text/templates. Returns a map of component name → template.
func loadComponentTemplates(fsys embed.FS) map[string]*template.Template {
	components := make(map[string]*template.Template)
	dir := "ui_main/components"
	entries, err := fs.ReadDir(fsys, dir)
	if err != nil {
		return components
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".html") {
			continue
		}
		data, err := fs.ReadFile(fsys, dir+"/"+e.Name())
		if err != nil {
			logWarn("Failed to read component %s: %v", e.Name(), err)
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".html")
		tmpl, err := template.New(name).Option("missingkey=zero").Parse(string(data))
		if err != nil {
			logWarn("Failed to parse component %s: %v", name, err)
			continue
		}
		components[name] = tmpl
	}
	return components
}

// expandComponents replaces <!-- @component-name ... --> markers with rendered HTML.
func expandComponents(html string, components map[string]*template.Template) string {
	if len(components) == 0 {
		return html
	}
	return componentMarkerRE.ReplaceAllStringFunc(html, func(match string) string {
		parts := componentMarkerRE.FindStringSubmatch(match)
		if len(parts) < 3 {
			return match
		}
		name := parts[1]
		tmpl, ok := components[name]
		if !ok {
			return match // not a component marker, leave as-is
		}
		attrs := parseComponentAttrs(parts[2])
		var buf strings.Builder
		if err := tmpl.Execute(&buf, attrs); err != nil {
			logWarn("Component @%s expansion failed: %v", name, err)
			return match
		}
		return buf.String()
	})
}

// parseComponentAttrs extracts key="value" pairs and boolean flags from a marker attribute string.
func parseComponentAttrs(raw string) map[string]string {
	attrs := make(map[string]string)
	for _, m := range componentAttrRE.FindAllStringSubmatch(raw, -1) {
		attrs[m[1]] = m[2]
	}
	// Boolean flags: remaining words after stripping key="value" pairs
	stripped := strings.TrimSpace(componentAttrRE.ReplaceAllString(raw, ""))
	if stripped != "" {
		for _, flag := range strings.Fields(stripped) {
			if regexp.MustCompile(`^\w[\w-]*$`).MatchString(flag) {
				attrs[flag] = "true"
			}
		}
	}
	return attrs
}
