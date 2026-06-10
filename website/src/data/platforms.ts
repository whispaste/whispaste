/**
 * platforms.ts — Single Source of Truth for platform/store metadata.
 *
 * Three public exports:
 *   1. `detectOs(input)` — pure function, no DOM, testable.
 *   2. `STORES` — static per-platform metadata (download URLs, product IDs,
 *      review URLs, store-listing flags).
 *   3. `resolvePrimary(os)` — returns the primary `PlatformOffer` for a given OS.
 *
 * Consumers (StoreButton, AppleButton, Layout head-script, platform.ts) read
 * exclusively from this file — no literal URLs or product IDs elsewhere.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type Os = 'windows' | 'macos' | 'linux' | 'unknown';

export interface PlatformOffer {
  /** Primary download URL for this platform. */
  downloadUrl: string;
  /** Human-readable architecture label (e.g. "arm64"). */
  arch: string[];
  /** Store product ID (e.g. MS Store ID). Empty string if not applicable. */
  storeProductId: string;
  /**
   * Review / rating URL for this platform's store.
   * Empty string when no valid store listing exists.
   */
  reviewUrl: string;
  /**
   * Whether an official store listing exists for this platform.
   * false = direct download only; do not link to a store listing page.
   */
  hasStoreListing: boolean;
}

// ---------------------------------------------------------------------------
// Input shape for detectOs — allows injecting UA data without DOM access
// ---------------------------------------------------------------------------

export interface OsDetectionInput {
  /** `navigator.userAgent` string. */
  userAgent: string;
  /**
   * Optional platform string from `navigator.userAgentData.platform`
   * (User-Agent Client Hints API). Presence takes priority over UA sniffing.
   */
  uadPlatform?: string | undefined;
}

// ---------------------------------------------------------------------------
// detectOs — pure function, no DOM access
// ---------------------------------------------------------------------------

/**
 * Detect the host OS from the supplied UA information.
 *
 * Priority: User-Agent Client Hints (`uadPlatform`) → UA string regex.
 * Mobile devices (iPhone, iPad, Android) always resolve to `'unknown'`
 * because WhisPaste is a desktop app and should not show download CTAs for
 * mobile visitors.
 *
 * @param input - `{ userAgent, uadPlatform? }`
 * @returns `'windows' | 'macos' | 'linux' | 'unknown'`
 */
export function detectOs(input: OsDetectionInput): Os {
  const { userAgent, uadPlatform } = input;

  // Mobile guard: never claim a desktop OS for phone/tablet agents.
  if (/iPhone|iPad|iPod|Android/.test(userAgent)) {
    return 'unknown';
  }

  // User-Agent Client Hints take priority (Chromium-based browsers).
  if (uadPlatform) {
    const p = uadPlatform.toLowerCase();
    if (p === 'macos') return 'macos';
    if (p === 'windows') return 'windows';
    if (p === 'linux') return 'linux';
  }

  // Classic UA regex fallback.
  if (/Macintosh|MacIntel|Mac OS X/.test(userAgent)) return 'macos';
  if (/Windows/.test(userAgent)) return 'windows';
  if (/Linux/.test(userAgent)) return 'linux';

  return 'unknown';
}

// ---------------------------------------------------------------------------
// STORES — central store/platform metadata
// ---------------------------------------------------------------------------

const GITHUB_RELEASE_BASE =
  'https://github.com/whispaste/whispaste/releases/latest/download';

export const GITHUB_REPO_URL = 'https://github.com/whispaste/whispaste';

export const MS_STORE_PRODUCT_ID = '9p22jvkrq2v0';
export const MS_STORE_URL = `https://apps.microsoft.com/detail/${MS_STORE_PRODUCT_ID}`;
export const MS_STORE_REVIEW_URL = `https://apps.microsoft.com/detail/${MS_STORE_PRODUCT_ID}?activetab=pivot:reviewsTab`;

export const MACOS_DMG_URL = `${GITHUB_RELEASE_BASE}/WhisPaste-macos-arm64.dmg`;

/** Direct GitHub download for the Windows installer (.exe). */
export const WINDOWS_SETUP_URL = `${GITHUB_RELEASE_BASE}/WhisPaste-Setup.exe`;

/** Standalone diagnostics tool for Windows. */
export const DIAGNOSE_WINDOWS_URL = `${GITHUB_RELEASE_BASE}/WhisPaste-Diagnose.exe`;

/** Standalone diagnostics tool for macOS. */
export const DIAGNOSE_MACOS_URL = `${GITHUB_RELEASE_BASE}/WhisPaste-Diagnose-macOS.dmg`;

/**
 * Static per-platform metadata.
 *
 * `windows`: Microsoft Store is the primary distribution channel.
 * `macos`: GitHub DMG (arm64). No Apple App Store listing exists.
 * `linux`: GitHub source / planned; no binary artefact yet — treated as the
 *   same GitHub releases page until a Linux artefact ships.
 */
export const STORES: Record<Exclude<Os, 'unknown'>, PlatformOffer> = {
  windows: {
    downloadUrl: MS_STORE_URL,
    arch: ['x64'],
    storeProductId: MS_STORE_PRODUCT_ID,
    reviewUrl: MS_STORE_REVIEW_URL,
    hasStoreListing: true,
  },
  macos: {
    downloadUrl: MACOS_DMG_URL,
    arch: ['arm64'],
    storeProductId: '',
    // No Apple App Store listing exists. The review action for macOS users is
    // a GitHub star — same as the existing "Star on GitHub" CTA in Support/Modal.
    reviewUrl: GITHUB_REPO_URL,
    hasStoreListing: false,
  },
  linux: {
    downloadUrl: 'https://github.com/whispaste/whispaste/releases/latest',
    arch: [],
    storeProductId: '',
    reviewUrl: '',
    hasStoreListing: false,
  },
};

// ---------------------------------------------------------------------------
// resolvePrimary — picks the right offer for a detected OS
// ---------------------------------------------------------------------------

/**
 * Returns the `PlatformOffer` for the given OS.
 * Falls back to the Windows offer for `'unknown'` (widest reach).
 * This function is used at render time by components, not for gating.
 */
export function resolvePrimary(os: Os): PlatformOffer {
  if (os === 'unknown') return STORES.windows;
  return STORES[os];
}
