package main

import (
	"testing"
	"unsafe"
)

// TestNotifyIconDataWSize verifies that our notifyIconDataW struct size
// matches the systray library's struct (984 bytes). The library has a bug
// where Timeout and Version are two separate uint32 fields instead of a
// 4-byte union, adding 4 bytes + 4 bytes padding = 8 bytes total.
// Our struct uses correct field layout + trailing _pad to match cbSize.
func TestNotifyIconDataWSize(t *testing.T) {
	var nid notifyIconDataW
	got := unsafe.Sizeof(nid)
	// Must match systray library's struct size (984 on amd64)
	const want = 984
	if got != want {
		t.Errorf("notifyIconDataW size = %d, want %d (must match systray library)", got, want)
	}
}

// TestNotifyIconDataWOffsets verifies critical field offsets match
// the Windows NOTIFYICONDATAW C struct layout on amd64.
func TestNotifyIconDataWOffsets(t *testing.T) {
	var nid notifyIconDataW
	tests := []struct {
		name   string
		offset uintptr
		want   uintptr
	}{
		{"cbSize", unsafe.Offsetof(nid.cbSize), 0},
		{"hWnd", unsafe.Offsetof(nid.hWnd), 8},
		{"uID", unsafe.Offsetof(nid.uID), 16},
		{"hIcon", unsafe.Offsetof(nid.hIcon), 32},
		{"szTip", unsafe.Offsetof(nid.szTip), 40},
		{"szInfo", unsafe.Offsetof(nid.szInfo), 304},
		{"uVersion", unsafe.Offsetof(nid.uVersion), 816},
		{"szInfoTitle", unsafe.Offsetof(nid.szInfoTitle), 820},
		{"dwInfoFlags", unsafe.Offsetof(nid.dwInfoFlags), 948},
		{"guidItem", unsafe.Offsetof(nid.guidItem), 952},
		{"hBalloonIcon", unsafe.Offsetof(nid.hBalloonIcon), 968},
	}
	for _, tt := range tests {
		if tt.offset != tt.want {
			t.Errorf("%s offset = %d, want %d", tt.name, tt.offset, tt.want)
		}
	}
}
