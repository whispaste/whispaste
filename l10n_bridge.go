package main

import "github.com/whispaste/whispaste/internal/i18n"

// T returns the localized string for the given key.
// Thin bridge to internal/i18n package to avoid updating 40+ call sites.
func T(key string) string { return i18n.T(key) }

func SetLanguage(lang string)      { i18n.SetLanguage(lang) }
func GetLanguage() string          { return i18n.GetLanguage() }
func SupportedLanguages() []string { return i18n.SupportedLanguages() }
