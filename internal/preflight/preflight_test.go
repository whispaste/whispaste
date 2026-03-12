package preflight

import "testing"

func TestResolveReasonCode(t *testing.T) {
	t.Run("keeps explicit reason", func(t *testing.T) {
		got := resolveReasonCode(StatusWarn, checkRAM, checkCores)
		if got != checkRAM {
			t.Fatalf("resolveReasonCode() = %q, want %q", got, checkRAM)
		}
	})

	t.Run("uses first warning code", func(t *testing.T) {
		got := resolveReasonCode(StatusWarn, "", checkCores)
		if got != checkCores {
			t.Fatalf("resolveReasonCode() = %q, want %q", got, checkCores)
		}
	})

	t.Run("warn falls back to avx2 only when needed", func(t *testing.T) {
		got := resolveReasonCode(StatusWarn, "", "")
		if got != checkAVX2 {
			t.Fatalf("resolveReasonCode() = %q, want %q", got, checkAVX2)
		}
	})

	t.Run("pass defaults to ready", func(t *testing.T) {
		got := resolveReasonCode(StatusPass, "", "")
		if got != "ready" {
			t.Fatalf("resolveReasonCode() = %q, want %q", got, "ready")
		}
	})
}
