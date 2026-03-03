package main

import (
	"os"
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

const autostartRegKey = `Software\Microsoft\Windows\CurrentVersion\Run`
const autostartValueName = "Whispaste"

// GetAutostart checks whether the app is configured to start on Windows login.
func GetAutostart() bool {
	if isStorePackage() {
		return false // MSIX Store packages use a different mechanism
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, autostartRegKey, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	_, _, err = k.GetStringValue(autostartValueName)
	return err == nil
}

// SetAutostart enables or disables the Windows autostart entry.
func SetAutostart(enable bool) error {
	if isStorePackage() {
		return nil // MSIX Store packages use a different mechanism
	}
	if enable {
		exe, err := os.Executable()
		if err != nil {
			return err
		}
		exe, err = filepath.Abs(exe)
		if err != nil {
			return err
		}
		k, _, err := registry.CreateKey(registry.CURRENT_USER, autostartRegKey, registry.SET_VALUE)
		if err != nil {
			return err
		}
		defer k.Close()
		return k.SetStringValue(autostartValueName, `"`+exe+`"`)
	}
	// Disable: delete the registry value
	k, err := registry.OpenKey(registry.CURRENT_USER, autostartRegKey, registry.SET_VALUE)
	if err != nil {
		return nil // Key doesn't exist, nothing to remove
	}
	defer k.Close()
	_ = k.DeleteValue(autostartValueName)
	return nil
}
