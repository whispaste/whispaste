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

func TestCheckMemoryBytes(t *testing.T) {
	t.Run("fails below 8 gib", func(t *testing.T) {
		facts := &Facts{}
		got := checkMemoryBytes((8<<30)-1, facts)
		if got.Status != StatusFail {
			t.Fatalf("checkMemoryBytes() status = %q, want %q", got.Status, StatusFail)
		}
		if !got.Blocking {
			t.Fatal("checkMemoryBytes() should block below 8 GiB")
		}
		if facts.MemoryBytes != (8<<30)-1 {
			t.Fatalf("facts.MemoryBytes = %d, want %d", facts.MemoryBytes, (8<<30)-1)
		}
	})

	t.Run("passes at 8 gib", func(t *testing.T) {
		facts := &Facts{}
		got := checkMemoryBytes(8<<30, facts)
		if got.Status != StatusPass {
			t.Fatalf("checkMemoryBytes() status = %q, want %q", got.Status, StatusPass)
		}
		if got.Blocking {
			t.Fatal("checkMemoryBytes() should not block at 8 GiB")
		}
	})
}
