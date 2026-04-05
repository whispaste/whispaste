module github.com/whispaste/go_backend

go 1.26

// Minimal Go FFI bridge for WhisPaste Flutter.
//
// Most functionality is reimplemented in pure Dart:
//   - Config: shared_preferences + JSON file
//   - History: drift (SQLite)
//   - Audio: record package
//   - HTTP APIs: dio
//   - Clipboard: super_clipboard
//
// This Go bridge handles ONLY platform-specific tasks
// that are impractical in Dart:
//   - GPU detection (nvidia-smi, WMI, sysfs, IOKit)
//   - Subprocess management for whisper-server / llama-server
//   - Platform paste simulation (SendInput, xdotool, CGEvent)

require golang.org/x/sys v0.42.0
