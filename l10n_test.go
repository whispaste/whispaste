package main

import (
	"testing"
)

func TestTFunction(t *testing.T) {
	SetLanguage("en")
	if got := T("app.name"); got != "WhisPaste" {
		t.Errorf("T(app.name) = %q, want WhisPaste", got)
	}
	if got := T("tray.quit"); got != "Quit" {
		t.Errorf("T(tray.quit) = %q, want Quit", got)
	}
}

func TestTFunctionGerman(t *testing.T) {
	SetLanguage("de")
	defer SetLanguage("en")

	if got := T("tray.quit"); got != "Beenden" {
		t.Errorf("T(tray.quit) in DE = %q, want Beenden", got)
	}
	if got := T("settings.title"); got != "Einstellungen" {
		t.Errorf("T(settings.title) in DE = %q, want Einstellungen", got)
	}
}

func TestTFunctionFallback(t *testing.T) {
	SetLanguage("en")
	// Unknown key should return the key itself
	if got := T("nonexistent.key"); got != "nonexistent.key" {
		t.Errorf("T(nonexistent.key) = %q, want nonexistent.key", got)
	}
}

func TestSetLanguageInvalid(t *testing.T) {
	SetLanguage("en")
	SetLanguage("xx") // unsupported
	if got := GetLanguage(); got != "en" {
		t.Errorf("SetLanguage(xx) changed language to %q, should stay en", got)
	}
}

func TestGetLanguage(t *testing.T) {
	SetLanguage("de")
	if got := GetLanguage(); got != "de" {
		t.Errorf("GetLanguage() = %q, want de", got)
	}
	SetLanguage("en")
	if got := GetLanguage(); got != "en" {
		t.Errorf("GetLanguage() = %q, want en", got)
	}
}

func TestSupportedLanguages(t *testing.T) {
	langs := SupportedLanguages()
	if len(langs) < 2 {
		t.Fatalf("SupportedLanguages() returned %d languages, want >= 2", len(langs))
	}
	has := make(map[string]bool)
	for _, l := range langs {
		has[l] = true
	}
	if !has["en"] {
		t.Error("en not in SupportedLanguages")
	}
	if !has["de"] {
		t.Error("de not in SupportedLanguages")
	}
}

func TestTranslationCompleteness(t *testing.T) {
	en := translations["en"]
	de := translations["de"]

	// Every EN key must exist in DE
	for key := range en {
		if _, ok := de[key]; !ok {
			t.Errorf("DE translation missing key: %q", key)
		}
	}
	// Every DE key must exist in EN
	for key := range de {
		if _, ok := en[key]; !ok {
			t.Errorf("EN translation missing key: %q (exists in DE but not EN)", key)
		}
	}
}

func TestTranslationNoEmpty(t *testing.T) {
	for lang, trans := range translations {
		for key, val := range trans {
			if val == "" {
				t.Errorf("%s: translation %q has empty value", lang, key)
			}
		}
	}
}

func TestTConcurrency(t *testing.T) {
	done := make(chan struct{})
	go func() {
		for i := 0; i < 200; i++ {
			T("app.name")
			T("tray.quit")
			T("settings.title")
		}
		close(done)
	}()

	for i := 0; i < 100; i++ {
		SetLanguage("de")
		SetLanguage("en")
	}
	<-done
}
