//go:build windows

package main

import "testing"

func TestAssumeFocusedInput(t *testing.T) {
	tests := []struct {
		name    string
		class   string
		appName string
		want    bool
	}{
		{name: "terminal class", class: "ConsoleWindowClass", appName: "cmd.exe", want: true},
		{name: "outlook app", class: "rctrl_renwnd32", appName: "outlook.exe", want: true},
		{name: "unknown app", class: "Notepad", appName: "notepad.exe", want: false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := assumeFocusedInput(tc.class, tc.appName); got != tc.want {
				t.Fatalf("assumeFocusedInput(%q, %q) = %v, want %v", tc.class, tc.appName, got, tc.want)
			}
		})
	}
}
