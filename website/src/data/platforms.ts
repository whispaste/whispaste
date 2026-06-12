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
  /** Machine-readable architecture identifiers (e.g. ["arm64"]). */
  arch: string[];
  /**
   * Human-readable architecture label for display purposes.
   * Empty string when no single-arch label is needed (multi-arch or unknown).
   * Example: "Apple Silicon (arm64)" for the macOS DMG.
   */
  archLabel: string;
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
    archLabel: '',
    storeProductId: MS_STORE_PRODUCT_ID,
    reviewUrl: MS_STORE_REVIEW_URL,
    hasStoreListing: true,
  },
  macos: {
    downloadUrl: MACOS_DMG_URL,
    arch: ['arm64'],
    /**
     * Human-readable architecture label shown next to the macOS download.
     * Only one build exists — Apple Silicon (arm64). No Intel/x64 build.
     * The i18n counterpart is `platform.macos.archLabel` (DE+EN).
     */
    archLabel: 'Apple Silicon (arm64)',
    storeProductId: '',
    // No Apple App Store listing exists. The review action for macOS users is
    // a GitHub star — same as the existing "Star on GitHub" CTA in Support/Modal.
    reviewUrl: GITHUB_REPO_URL,
    hasStoreListing: false,
  },
  linux: {
    downloadUrl: 'https://github.com/whispaste/whispaste/releases/latest',
    arch: [],
    archLabel: '',
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

// ---------------------------------------------------------------------------
// Package-manager channels — SSoT for Scoop / winget / Homebrew
// ---------------------------------------------------------------------------

export type PkgManagerId = 'scoop' | 'winget' | 'homebrew';

export interface PkgManagerChannel {
  /** Unique identifier for this channel. */
  id: PkgManagerId;
  /**
   * Whether this channel is live/published.
   * false → channel not yet published; must NOT be rendered on the website.
   * Guards winget and Homebrew until they are submitted and verified.
   */
  live: boolean;
  /** Platform this channel targets. */
  platform: Exclude<Os, 'unknown'>;
  /** Install/update commands shown verbatim in the code block. */
  commands: string[];
  /**
   * Bilingual comment line displayed above the commands (code-block header).
   * Keyed by locale so both DE and EN pages can read from the same source.
   */
  comment: { de: string; en: string };
}

/**
 * Package-manager channels for WhisPaste.
 *
 * Consumers (download.astro, en/download.astro) import this array and call
 * getLivePkgManagers() — no literal commands or channel names elsewhere.
 *
 * live: true  → rendered on the download page immediately.
 * live: false → channel not yet published; suppressed by getLivePkgManagers().
 *               Flip to true once the channel is verified and live.
 */
export const PKG_MANAGERS: PkgManagerChannel[] = [
  {
    id: 'scoop',
    live: true,
    platform: 'windows',
    commands: [
      'scoop bucket add whispaste https://github.com/whispaste/scoop-bucket',
      'scoop install whispaste',
    ],
    comment: { de: '# Windows · Scoop', en: '# Windows · Scoop' },
  },
  {
    id: 'winget',
    live: false,
    platform: 'windows',
    commands: ['winget install whispaste.whispaste'],
    comment: { de: '# Windows · winget', en: '# Windows · winget' },
  },
  {
    id: 'homebrew',
    live: false,
    platform: 'macos',
    commands: ['brew install --cask whispaste'],
    comment: { de: '# macOS · Homebrew', en: '# macOS · Homebrew' },
  },
];

/**
 * Returns only the live/published package-manager channels.
 * Use this to filter what gets rendered on the website — channels with
 * live: false are not yet published and must not appear on the page.
 */
export function getLivePkgManagers(): PkgManagerChannel[] {
  return PKG_MANAGERS.filter((ch) => ch.live);
}
