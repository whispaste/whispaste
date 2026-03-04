package main

import (
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
// format must be "txt" or "md". Returns the file path on success or empty string.
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

	if err := os.WriteFile(path, []byte(content.String()), 0644); err != nil {
		logError("Export write failed: %v", err)
		return ""
	}

	logInfo("Exported %d entries to %s", len(entries), path)
	return path
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
