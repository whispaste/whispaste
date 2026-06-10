/**
 * Tests for `detectOs` (pure OS-detection function) and `STORES` config
 * invariants (platforms.ts SSoT layer).
 *
 * Design: tests exercise *observable behaviour* — given a UA/uadPlatform
 * input, which OS string is returned; given the STORES config, which
 * invariants hold. No internal regex is tested directly.
 */
import { describe, expect, it } from "vitest";
import {
  detectOs,
  STORES,
  resolvePrimary,
  MS_STORE_PRODUCT_ID,
  type OsDetectionInput,
} from "../platforms.ts";

// ---------------------------------------------------------------------------
// detectOs — UA table tests
// ---------------------------------------------------------------------------

describe("detectOs", () => {
  // Helper to shorten table entries
  function detect(userAgent: string, uadPlatform?: string) {
    return detectOs({ userAgent, uadPlatform } as OsDetectionInput);
  }

  // --- Windows ---
  it("returns 'windows' for a Windows 10 Chrome UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      )
    ).toBe("windows");
  });

  it("returns 'windows' for a Windows 11 Edge UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
      )
    ).toBe("windows");
  });

  // --- macOS / Safari ---
  it("returns 'macos' for a macOS Safari UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
      )
    ).toBe("macos");
  });

  it("returns 'macos' for a macOS Chrome UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      )
    ).toBe("macos");
  });

  // --- macOS via userAgentData (Client Hints) ---
  it("returns 'macos' when uadPlatform is 'macOS' (Chrome on Apple Silicon)", () => {
    expect(
      detect(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "macOS"
      )
    ).toBe("macos");
  });

  it("returns 'windows' when uadPlatform is 'Windows' (Chrome on Windows)", () => {
    expect(
      detect(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Windows"
      )
    ).toBe("windows");
  });

  // --- Linux ---
  it("returns 'linux' for a Linux Chrome UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      )
    ).toBe("linux");
  });

  it("returns 'linux' when uadPlatform is 'Linux'", () => {
    expect(detect("Mozilla/5.0 (X11; Linux x86_64) ...", "Linux")).toBe(
      "linux"
    );
  });

  // --- Mobile → unknown ---
  it("returns 'unknown' for an iPhone UA (iOS)", () => {
    expect(
      detect(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
      )
    ).toBe("unknown");
  });

  it("returns 'unknown' for an iPad UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
      )
    ).toBe("unknown");
  });

  it("returns 'unknown' for an Android Chrome UA", () => {
    expect(
      detect(
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
      )
    ).toBe("unknown");
  });

  // --- Unknown / empty ---
  it("returns 'unknown' for an empty UA string", () => {
    expect(detect("")).toBe("unknown");
  });

  it("returns 'unknown' for an unrecognised UA string", () => {
    expect(detect("SomeBotCrawler/1.0")).toBe("unknown");
  });

  // --- uadPlatform takes priority over UA string ---
  it("prefers uadPlatform over UA when both are present", () => {
    // UA says macOS but uadPlatform says Windows — Client Hints wins.
    expect(
      detect(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Windows"
      )
    ).toBe("windows");
  });
});

// ---------------------------------------------------------------------------
// STORES config invariants
// ---------------------------------------------------------------------------

describe("STORES config invariants", () => {
  const platforms = ["windows", "macos", "linux"] as const;

  it("every platform has a non-empty primary download URL", () => {
    for (const p of platforms) {
      expect(
        STORES[p].downloadUrl,
        `${p}.downloadUrl must be non-empty`
      ).toBeTruthy();
    }
  });

  it("all non-empty URLs are well-formed (start with https://)", () => {
    for (const p of platforms) {
      const offer = STORES[p];
      for (const url of [offer.downloadUrl, offer.reviewUrl]) {
        if (url) {
          expect(
            url,
            `${p} URL "${url}" must start with https://`
          ).toMatch(/^https:\/\//);
        }
      }
    }
  });

  it("no platform references a store listing that is marked as non-existent", () => {
    for (const p of platforms) {
      const offer = STORES[p];
      if (!offer.hasStoreListing) {
        expect(
          offer.storeProductId,
          `${p} has hasStoreListing=false but a non-empty storeProductId`
        ).toBe("");
        // reviewUrl may be empty or point to non-store feedback (e.g. GitHub).
        // If it references apps.apple.com it must contain /id to be valid.
        if (offer.reviewUrl.includes("apps.apple.com")) {
          expect(
            offer.reviewUrl,
            `${p} Apple review URL must contain /id to be structurally valid`
          ).toMatch(/\/id\d+/);
        }
      }
    }
  });

  it("Windows platform has the correct MS Store product ID", () => {
    expect(STORES.windows.storeProductId).toBe(MS_STORE_PRODUCT_ID);
    expect(STORES.windows.storeProductId).toBe("9p22jvkrq2v0");
  });

  it("macOS DMG URL references the arm64 artefact", () => {
    expect(STORES.macos.downloadUrl).toContain("arm64");
  });

  it("macOS has no Apple Store listing (flag=false, no storeProductId)", () => {
    expect(STORES.macos.hasStoreListing).toBe(false);
    expect(STORES.macos.storeProductId).toBe("");
  });

  it("macOS reviewUrl is empty (no valid Apple Store listing)", () => {
    expect(STORES.macos.reviewUrl).toBe("");
  });
});

// ---------------------------------------------------------------------------
// resolvePrimary
// ---------------------------------------------------------------------------

describe("resolvePrimary", () => {
  it("returns the windows offer for 'windows'", () => {
    expect(resolvePrimary("windows")).toBe(STORES.windows);
  });

  it("returns the macos offer for 'macos'", () => {
    expect(resolvePrimary("macos")).toBe(STORES.macos);
  });

  it("returns the linux offer for 'linux'", () => {
    expect(resolvePrimary("linux")).toBe(STORES.linux);
  });

  it("returns the windows offer for 'unknown' (widest-reach fallback)", () => {
    expect(resolvePrimary("unknown")).toBe(STORES.windows);
  });
});
