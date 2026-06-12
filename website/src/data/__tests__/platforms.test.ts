/**
 * Tests for `detectOs` (pure OS-detection function) and `STORES` config
 * invariants (platforms.ts SSoT layer).
 *
 * Design: tests exercise *observable behaviour* — given a UA/uadPlatform
 * input, which OS string is returned; given the STORES config, which
 * invariants hold. No internal regex is tested directly.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  detectOs,
  STORES,
  resolvePrimary,
  PKG_MANAGERS,
  getLivePkgManagers,
  MS_STORE_PRODUCT_ID,
  GITHUB_REPO_URL,
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

  it("macOS arch is ['arm64'] — only Apple Silicon build, no Intel/x64", () => {
    expect(STORES.macos.arch).toEqual(["arm64"]);
    expect(STORES.macos.arch).not.toContain("x64");
    expect(STORES.macos.arch).not.toContain("x86_64");
  });

  it("macOS archLabel is 'Apple Silicon (arm64)'", () => {
    expect(STORES.macos.archLabel).toBe("Apple Silicon (arm64)");
  });

  it("macOS archLabel contains 'arm64'", () => {
    expect(STORES.macos.archLabel).toContain("arm64");
  });

  it("windows and linux have empty archLabel (multi-arch or not applicable)", () => {
    expect(STORES.windows.archLabel).toBe("");
    expect(STORES.linux.archLabel).toBe("");
  });

  it("macOS has no Apple Store listing (flag=false, no storeProductId)", () => {
    expect(STORES.macos.hasStoreListing).toBe(false);
    expect(STORES.macos.storeProductId).toBe("");
  });

  it("macOS reviewUrl points to the GitHub repo (no Apple Store listing — GitHub star is the review path)", () => {
    expect(STORES.macos.reviewUrl).toBe(GITHUB_REPO_URL);
    expect(STORES.macos.reviewUrl).toMatch(/^https:\/\/github\.com\//);
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

// ---------------------------------------------------------------------------
// PKG_MANAGERS — package-manager channel SSoT
// ---------------------------------------------------------------------------

describe("PKG_MANAGERS config invariants", () => {
  it("exports PKG_MANAGERS as a non-empty array", () => {
    expect(Array.isArray(PKG_MANAGERS)).toBe(true);
    expect(PKG_MANAGERS.length).toBeGreaterThan(0);
  });

  it("scoop is live (renders immediately on the download page)", () => {
    const scoop = PKG_MANAGERS.find((m) => m.id === "scoop");
    expect(scoop, "scoop channel must exist").toBeDefined();
    expect(scoop!.live).toBe(true);
  });

  it("winget is NOT live (behind live-guard — not yet published)", () => {
    const winget = PKG_MANAGERS.find((m) => m.id === "winget");
    expect(winget, "winget channel must exist").toBeDefined();
    expect(winget!.live).toBe(false);
  });

  it("homebrew is NOT live (behind live-guard — not yet published)", () => {
    const homebrew = PKG_MANAGERS.find((m) => m.id === "homebrew");
    expect(homebrew, "homebrew channel must exist").toBeDefined();
    expect(homebrew!.live).toBe(false);
  });

  it("all channels have at least one non-empty command", () => {
    for (const ch of PKG_MANAGERS) {
      expect(
        ch.commands.length,
        `${ch.id}.commands must be non-empty`
      ).toBeGreaterThan(0);
      for (const cmd of ch.commands) {
        expect(cmd.trim(), `${ch.id}: empty command string`).not.toBe("");
      }
    }
  });

  it("all channels have bilingual comment labels (de + en)", () => {
    for (const ch of PKG_MANAGERS) {
      expect(
        ch.comment.de,
        `${ch.id}.comment.de must be non-empty`
      ).toBeTruthy();
      expect(
        ch.comment.en,
        `${ch.id}.comment.en must be non-empty`
      ).toBeTruthy();
    }
  });
});

// ---------------------------------------------------------------------------
// getLivePkgManagers — live-guard filter
// ---------------------------------------------------------------------------

describe("getLivePkgManagers", () => {
  it("returns only channels with live: true", () => {
    const live = getLivePkgManagers();
    expect(live.every((m) => m.live)).toBe(true);
  });

  it("does NOT include winget (not yet published)", () => {
    const ids = getLivePkgManagers().map((m) => m.id);
    expect(ids).not.toContain("winget");
  });

  it("does NOT include homebrew (not yet published)", () => {
    const ids = getLivePkgManagers().map((m) => m.id);
    expect(ids).not.toContain("homebrew");
  });

  it("includes scoop (live)", () => {
    const ids = getLivePkgManagers().map((m) => m.id);
    expect(ids).toContain("scoop");
  });
});

// ---------------------------------------------------------------------------
// SSoT enforcement — no literal package-manager commands in download pages
// ---------------------------------------------------------------------------

describe("SSoT: no literal package-manager commands in download pages", () => {
  // Resolve paths relative to this test file's location (src/data/__tests__/).
  const thisDir = dirname(fileURLToPath(import.meta.url));
  const deDownload = readFileSync(
    resolve(thisDir, "../../pages/download.astro"),
    "utf8"
  );
  const enDownload = readFileSync(
    resolve(thisDir, "../../pages/en/download.astro"),
    "utf8"
  );

  // The Scoop bucket-add command is the canonical canary for "literals exist".
  const scoopBucketCmd = "scoop bucket add whispaste https://github.com/whispaste/scoop-bucket";

  it("DE download.astro contains no literal Scoop bucket command", () => {
    expect(deDownload).not.toContain(scoopBucketCmd);
  });

  it("EN en/download.astro contains no literal Scoop bucket command", () => {
    expect(enDownload).not.toContain(scoopBucketCmd);
  });

  it("DE download.astro imports getLivePkgManagers from platforms.ts (data-driven)", () => {
    expect(deDownload).toContain("getLivePkgManagers");
  });

  it("EN en/download.astro imports getLivePkgManagers from platforms.ts (data-driven)", () => {
    expect(enDownload).toContain("getLivePkgManagers");
  });

  it("both pages render the pkg-managers block (data-testid)", () => {
    expect(deDownload).toContain('data-testid="pkg-managers"');
    expect(enDownload).toContain('data-testid="pkg-managers"');
  });
});
