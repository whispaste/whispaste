package main

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"os"
	"strings"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	comdlg32          = windows.NewLazySystemDLL("comdlg32.dll")
	procGetSaveFileNameW = comdlg32.NewProc("GetSaveFileNameW")
)

// OPENFILENAMEW is the Windows OPENFILENAME struct for GetSaveFileNameW.
type openFileNameW struct {
	StructSize      uint32
	Owner           uintptr
	Instance        uintptr
	Filter          *uint16
	CustomFilter    *uint16
	MaxCustomFilter uint32
	FilterIndex     uint32
	File            *uint16
	MaxFile         uint32
	FileTitle       *uint16
	MaxFileTitle    uint32
	InitialDir      *uint16
	Title           *uint16
	Flags           uint32
	FileOffset      uint16
	FileExtension   uint16
	DefExt          *uint16
	CustData        uintptr
	FnHook          uintptr
	TemplateName    *uint16
	PvReserved      uintptr
	DwReserved      uint32
	FlagsEx         uint32
}

const (
	ofnOverwritePrompt = 0x00000002
	ofnNoChangeDir     = 0x00000008
	ofnExplorer        = 0x00080000
)

// showSaveDialog opens a Windows Save File dialog and returns the chosen path.
// Returns empty string if the user cancels.
func showSaveDialog(title string, defaultName string, filter string) string {
	filterUTF16, _ := windows.UTF16PtrFromString(strings.ReplaceAll(filter, "|", "\x00") + "\x00")
	titleUTF16, _ := windows.UTF16PtrFromString(title)

	fileBuf := make([]uint16, 260)
	nameUTF16, _ := windows.UTF16FromString(defaultName)
	copy(fileBuf, nameUTF16)

	ofn := openFileNameW{
		StructSize: uint32(unsafe.Sizeof(openFileNameW{})),
		Filter:     filterUTF16,
		File:       &fileBuf[0],
		MaxFile:    uint32(len(fileBuf)),
		Title:      titleUTF16,
		Flags:      ofnOverwritePrompt | ofnNoChangeDir | ofnExplorer,
	}

	ret, _, _ := procGetSaveFileNameW.Call(uintptr(unsafe.Pointer(&ofn)))
	if ret == 0 {
		return "" // cancelled
	}
	return windows.UTF16ToString(fileBuf)
}

// formatEntryTXT formats a single entry as plain text.
func formatEntryTXT(e *HistoryEntry) string {
	var b strings.Builder
	b.WriteString(e.Title)
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("Date: %s\n", e.Timestamp))
	if e.Language != "" {
		b.WriteString(fmt.Sprintf("Language: %s\n", e.Language))
	}
	if len(e.Tags) > 0 {
		b.WriteString(fmt.Sprintf("Tags: %s\n", strings.Join(e.Tags, ", ")))
	}
	b.WriteString("\n")
	b.WriteString(e.Text)
	b.WriteString("\n")
	return b.String()
}

// formatEntryMD formats a single entry as Markdown.
func formatEntryMD(e *HistoryEntry) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("# %s\n\n", e.Title))
	b.WriteString(fmt.Sprintf("- **Date:** %s\n", e.Timestamp))
	if e.Language != "" {
		b.WriteString(fmt.Sprintf("- **Language:** %s\n", strings.ToUpper(e.Language)))
	}
	if e.Duration > 0 {
		b.WriteString(fmt.Sprintf("- **Duration:** %.1fs\n", e.Duration))
	}
	if len(e.Tags) > 0 {
		tagStr := make([]string, len(e.Tags))
		for i, t := range e.Tags {
			tagStr[i] = "`" + t + "`"
		}
		b.WriteString(fmt.Sprintf("- **Tags:** %s\n", strings.Join(tagStr, ", ")))
	}
	b.WriteString("\n")
	b.WriteString(e.Text)
	b.WriteString("\n")
	return b.String()
}

// exportEntries formats multiple entries and writes them to a file chosen by the user.
// format must be "txt", "md", "json", "csv", or "docx". Returns the file path on success or empty string.
func exportEntries(entries []*HistoryEntry, format string) string {
	if len(entries) == 0 {
		return ""
	}

	var ext, filterStr, defName string
	switch format {
	case "md":
		ext = ".md"
		filterStr = "Markdown (*.md)|*.md|All Files (*.*)|*.*"
		defName = "whispaste-export.md"
	case "json":
		ext = ".json"
		filterStr = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
		defName = "whispaste-export.json"
	case "csv":
		ext = ".csv"
		filterStr = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"
		defName = "whispaste-export.csv"
	case "docx":
		ext = ".docx"
		filterStr = "Word Documents (*.docx)|*.docx|All Files (*.*)|*.*"
		defName = "whispaste-export.docx"
	default:
		ext = ".txt"
		filterStr = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
		defName = "whispaste-export.txt"
	}

	if len(entries) == 1 {
		safe := sanitizeFilename(entries[0].Title)
		if safe != "" {
			defName = safe + ext
		}
	}

	path := showSaveDialog("Export", defName, filterStr)
	if path == "" {
		return "" // user cancelled
	}

	var data []byte
	var err error

	switch format {
	case "json":
		data, err = formatEntriesJSON(entries)
	case "csv":
		data, err = formatEntriesCSV(entries)
	case "docx":
		data, err = generateDOCX(entries)
	default:
		var content strings.Builder
		for i, e := range entries {
			switch format {
			case "md":
				content.WriteString(formatEntryMD(e))
			default:
				content.WriteString(formatEntryTXT(e))
			}
			if i < len(entries)-1 {
				content.WriteString("\n---\n\n")
			}
		}
		data = []byte(content.String())
	}

	if err != nil {
		logError("Export format failed: %v", err)
		return ""
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		logError("Export write failed: %v", err)
		return ""
	}

	logInfo("Exported %d entries to %s", len(entries), path)
	return path
}

// formatEntriesJSON serializes entries as pretty-printed JSON.
func formatEntriesJSON(entries []*HistoryEntry) ([]byte, error) {
	data, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("json marshal: %w", err)
	}
	return append(data, '\n'), nil
}

// csvSafe prevents CSV formula injection by prefixing dangerous leading
// characters with a tab. Cells starting with =, +, -, or @ can be
// interpreted as formulas by spreadsheet applications.
func csvSafe(s string) string {
	if len(s) > 0 {
		switch s[0] {
		case '=', '+', '-', '@':
			return "\t" + s
		}
	}
	return s
}

// formatEntriesCSV serializes entries as CSV with a header row.
func formatEntriesCSV(entries []*HistoryEntry) ([]byte, error) {
	var buf strings.Builder
	w := csv.NewWriter(&buf)

	header := []string{"ID", "Title", "Text", "Timestamp", "Duration", "Language", "Tags", "Pinned", "Model", "IsLocal", "CostUSD"}
	if err := w.Write(header); err != nil {
		return nil, fmt.Errorf("csv header: %w", err)
	}

	for _, e := range entries {
		row := []string{
			e.ID,
			csvSafe(e.Title),
			csvSafe(e.Text),
			e.Timestamp,
			fmt.Sprintf("%.1f", e.Duration),
			e.Language,
			strings.Join(e.Tags, "|"),
			fmt.Sprintf("%t", e.Pinned),
			e.Model,
			fmt.Sprintf("%t", e.IsLocal),
			fmt.Sprintf("%.6f", e.CostUSD),
		}
		if err := w.Write(row); err != nil {
			return nil, fmt.Errorf("csv row %s: %w", e.ID, err)
		}
	}

	w.Flush()
	if err := w.Error(); err != nil {
		return nil, fmt.Errorf("csv flush: %w", err)
	}
	return []byte(buf.String()), nil
}

// generateDOCX creates a minimal DOCX file from history entries using stdlib only.
func generateDOCX(entries []*HistoryEntry) ([]byte, error) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	contentTypes := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>`

	rels := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`

	wordRels := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`

	styles := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:pPr><w:spacing w:before="360" w:after="120"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="1A1A2E"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Meta">
    <w:name w:val="Meta"/>
    <w:pPr><w:spacing w:after="40"/></w:pPr>
    <w:rPr><w:sz w:val="18"/><w:color w:val="666666"/></w:rPr>
  </w:style>
</w:styles>`

	// Build document body
	var body strings.Builder
	for i, e := range entries {
		if i > 0 {
			// Page break between entries
			body.WriteString(`<w:p><w:r><w:br w:type="page"/></w:r></w:p>`)
		}
		// Heading 1: title
		body.WriteString(`<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>`)
		body.WriteString(`<w:r><w:t xml:space="preserve">`)
		body.WriteString(xmlEscape(e.Title))
		body.WriteString(`</w:t></w:r></w:p>`)

		// Metadata line
		meta := fmt.Sprintf("Date: %s", e.Timestamp)
		if e.Language != "" {
			meta += fmt.Sprintf("  |  Language: %s", strings.ToUpper(e.Language))
		}
		if e.Duration > 0 {
			meta += fmt.Sprintf("  |  Duration: %.1fs", e.Duration)
		}
		if e.Model != "" {
			meta += fmt.Sprintf("  |  Model: %s", e.Model)
		}
		body.WriteString(`<w:p><w:pPr><w:pStyle w:val="Meta"/></w:pPr>`)
		body.WriteString(`<w:r><w:t xml:space="preserve">`)
		body.WriteString(xmlEscape(meta))
		body.WriteString(`</w:t></w:r></w:p>`)

		// Tags line
		if len(e.Tags) > 0 {
			body.WriteString(`<w:p><w:pPr><w:pStyle w:val="Meta"/></w:pPr>`)
			body.WriteString(`<w:r><w:t xml:space="preserve">Tags: `)
			body.WriteString(xmlEscape(strings.Join(e.Tags, ", ")))
			body.WriteString(`</w:t></w:r></w:p>`)
		}

		// Empty line before body text
		body.WriteString(`<w:p/>`)

		// Body text — split into paragraphs on newlines
		for _, line := range strings.Split(e.Text, "\n") {
			body.WriteString(`<w:p><w:r><w:t xml:space="preserve">`)
			body.WriteString(xmlEscape(line))
			body.WriteString(`</w:t></w:r></w:p>`)
		}
	}

	document := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>` + body.String() + `</w:body>
</w:document>`

	files := map[string]string{
		"[Content_Types].xml":          contentTypes,
		"_rels/.rels":                  rels,
		"word/_rels/document.xml.rels": wordRels,
		"word/styles.xml":              styles,
		"word/document.xml":            document,
	}

	// Write files in deterministic order
	order := []string{"[Content_Types].xml", "_rels/.rels", "word/_rels/document.xml.rels", "word/styles.xml", "word/document.xml"}
	for _, name := range order {
		w, err := zw.Create(name)
		if err != nil {
			return nil, fmt.Errorf("docx create %s: %w", name, err)
		}
		if _, err := w.Write([]byte(files[name])); err != nil {
			return nil, fmt.Errorf("docx write %s: %w", name, err)
		}
	}

	if err := zw.Close(); err != nil {
		return nil, fmt.Errorf("docx close zip: %w", err)
	}
	return buf.Bytes(), nil
}

// xmlEscape escapes a string for safe inclusion in XML text content.
func xmlEscape(s string) string {
	var b strings.Builder
	if err := xml.EscapeText(&b, []byte(s)); err != nil {
		return s
	}
	return b.String()
}

// sanitizeFilename removes characters invalid for Windows filenames.
func sanitizeFilename(name string) string {
	name = strings.TrimSpace(name)
	if len(name) > 50 {
		name = name[:50]
	}
	replacer := strings.NewReplacer(
		`<`, "", `>`, "", `:`, "", `"`, "", `/`, "", `\`, "",
		`|`, "", `?`, "", `*`, "", "\n", " ", "\r", "",
	)
	return strings.TrimSpace(replacer.Replace(name))
}
