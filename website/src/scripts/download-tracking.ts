/**
 * Download measurement for the website (#1938).
 *
 * One Matomo event per click on a download or store link:
 *   category "Download", action = channel, name = placement.
 *
 * The channel comes from the link URL alone (`downloadChannel`), so every new
 * link to a store listing or a release asset is counted without extra markup.
 * The placement comes from the nearest `[data-download-placement]` ancestor
 * (hero, pricing, …) and otherwise from the page (`placementForPath`).
 *
 * Store links additionally carry the placement as a campaign parameter, so
 * Partner Center (`cid`) and App Store Connect (`ct`) can attribute store
 * page views and purchases to the surface the visitor came from. These
 * parameters only travel to the store the visitor is opening anyway; no new
 * request leaves the site.
 *
 * Schema and Matomo setup: internal-notes.
 */
import {
  GITHUB_REPO_URL,
  MAC_APP_STORE_ID,
  MAC_APP_STORE_URL,
  MS_STORE_PRODUCT_ID,
  MS_STORE_URL,
} from '../data/platforms.ts';
import { parsePath } from './locales.ts';

export type DownloadChannel =
  | 'store-ms'
  | 'store-mac'
  | 'github-exe'
  | 'github-portable'
  | 'github-dmg'
  | 'appimage'
  | 'deb'
  | 'rpm'
  | 'linux-tar'
  | 'flatpak'
  | 'snap'
  | 'github-releases'
  | 'source';

/** Matomo event category of the download event. */
export const DOWNLOAD_EVENT_CATEGORY = 'Download';

/**
 * File extensions Matomo's link tracking does not count as a download by
 * default (its built-in list already has exe, dmg, deb, rpm, zip, gz).
 * Matomo matches case-insensitively.
 */
export const EXTRA_DOWNLOAD_EXTENSIONS: readonly string[] = ['AppImage'];

/** Attribute on a container (or the link itself) naming its placement. */
export const PLACEMENT_ATTRIBUTE = 'data-download-placement';

/**
 * Opt-in for links whose URL alone is not a download (the repository root is
 * also the "star us" link in nav and footer). Value = channel, e.g. `source`.
 */
export const CHANNEL_ATTRIBUTE = 'data-download-channel';

// Hosts and paths come from the platform SSoT, never as literals here.
const MS_STORE_HOST = new URL(MS_STORE_URL).hostname;
const MAC_APP_STORE_HOST = new URL(MAC_APP_STORE_URL).hostname;
const REPO = new URL(GITHUB_REPO_URL);
const REPO_PATH = REPO.pathname.replace(/\/+$/, '').toLowerCase();
const CHANNELS: ReadonlySet<string> = new Set<DownloadChannel>([
  'store-ms',
  'store-mac',
  'github-exe',
  'github-portable',
  'github-dmg',
  'appimage',
  'deb',
  'rpm',
  'linux-tar',
  'flatpak',
  'snap',
  'github-releases',
  'source',
]);

function parseUrl(href: string): URL | null {
  try {
    return new URL(href, 'https://whispaste.de/');
  } catch {
    return null;
  }
}

function isMsStoreListing(url: URL): boolean {
  if (url.protocol === 'ms-windows-store:') {
    return url.href.toLowerCase().includes(MS_STORE_PRODUCT_ID);
  }
  return (
    url.hostname === MS_STORE_HOST &&
    url.pathname.toLowerCase().includes(`/detail/${MS_STORE_PRODUCT_ID}`) &&
    // The review tab is "rate us", not a download.
    !(url.searchParams.get('activetab') ?? '').toLowerCase().includes('review')
  );
}

function isMacStoreListing(url: URL): boolean {
  if (url.protocol === 'macappstore:' || url.protocol === 'itms-apps:') {
    return url.href.includes(MAC_APP_STORE_ID);
  }
  return (
    url.hostname === MAC_APP_STORE_HOST &&
    url.pathname.includes(`id${MAC_APP_STORE_ID}`) &&
    url.searchParams.get('action') !== 'write-review'
  );
}

function releaseAssetChannel(fileName: string): DownloadChannel | null {
  const name = fileName.toLowerCase();
  // Helper tools and GPU add-on packs are not the app itself.
  if (name.includes('diagnose') || name.includes('cuda')) return null;
  if (name.endsWith('.exe') || name.endsWith('.msi')) return 'github-exe';
  if (name.endsWith('.zip')) return 'github-portable';
  if (name.endsWith('.dmg')) return 'github-dmg';
  if (name.endsWith('.appimage')) return 'appimage';
  if (name.endsWith('.deb')) return 'deb';
  if (name.endsWith('.rpm')) return 'rpm';
  if (name.endsWith('.tar.gz') || name.endsWith('.tgz')) return 'linux-tar';
  if (name.endsWith('.flatpak') || name.endsWith('.flatpakref')) return 'flatpak';
  if (name.endsWith('.snap')) return 'snap';
  return null;
}

/**
 * Download channel of a link target, or null when the link is not a way to
 * get the app (review links, docs on GitHub, diagnostics tools, …).
 */
export function downloadChannel(href: string): DownloadChannel | null {
  const url = parseUrl(href);
  if (!url) return null;
  if (isMsStoreListing(url)) return 'store-ms';
  if (isMacStoreListing(url)) return 'store-mac';
  if (url.hostname === 'flathub.org' && url.pathname.toLowerCase().includes('whispaste')) return 'flatpak';
  if (url.hostname === 'snapcraft.io' && url.pathname.toLowerCase().includes('whispaste')) return 'snap';
  if (url.hostname !== REPO.hostname) return null;
  const path = url.pathname.replace(/\/+$/, '');
  if (!path.toLowerCase().startsWith(`${REPO_PATH}/releases`)) return null;
  // Release assets: <repo>/releases/download/<tag>/<file> and the
  // "latest" alias form, where "download" follows "latest".
  const segments = path.slice(REPO_PATH.length).split('/').filter(Boolean);
  if (segments.includes('download')) {
    return releaseAssetChannel(segments[segments.length - 1] ?? '');
  }
  // Release list, a tagged release or /releases/latest: the visitor picks a file there.
  return 'github-releases';
}

/** Narrows an explicit `data-download-channel` value to a known channel. */
export function explicitChannel(value: string | null | undefined): DownloadChannel | null {
  return value && CHANNELS.has(value) ? (value as DownloadChannel) : null;
}

/**
 * Store campaign values are short slugs: Apple caps `ct` at 40 characters and
 * both stores show them verbatim in their reports.
 */
export function normalizePlacement(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 36)
    .replace(/-+$/, '');
  return slug || 'page';
}

/** Placement of a link that sits on no marked surface: the page it is on. */
export function placementForPath(pathname: string): string {
  const { slug } = parsePath(pathname);
  if (slug === '') return 'home';
  const first = slug.split('/')[0] ?? '';
  if (first === 'download') return 'download-page';
  if (first === 'vergleich') return 'comparison';
  return normalizePlacement(first);
}

/** Placement of a link: nearest marked surface, else the page. */
export function placementFor(link: Element, pathname: string): string {
  const marked = link.closest(`[${PLACEMENT_ATTRIBUTE}]`)?.getAttribute(PLACEMENT_ATTRIBUTE);
  return marked ? normalizePlacement(marked) : placementForPath(pathname);
}

/**
 * Prefix of every campaign value set by the website, so store reports keep
 * website surfaces apart from campaigns set elsewhere (videos, the app).
 */
export const STORE_CAMPAIGN_PREFIX = 'web-';

/**
 * Store URL with the placement as campaign parameter: `cid` for the
 * Microsoft Store, `ct` for the Mac App Store. No App Store provider token
 * (`pt`) exists for WhisPaste yet, so only `ct` is set. Other URLs are
 * returned unchanged; an existing campaign value is kept.
 */
export function withStoreCampaign(href: string, placement: string): string {
  const url = parseUrl(href);
  if (!url) return href;
  const campaign = `${STORE_CAMPAIGN_PREFIX}${normalizePlacement(placement)}`.slice(0, 40);
  if (url.protocol.startsWith('http') && isMsStoreListing(url)) {
    if (!url.searchParams.has('cid')) url.searchParams.set('cid', campaign);
    return url.href;
  }
  if (url.protocol.startsWith('http') && isMacStoreListing(url)) {
    if (!url.searchParams.has('ct')) url.searchParams.set('ct', campaign);
    return url.href;
  }
  return href;
}

export interface DownloadEvent {
  readonly channel: DownloadChannel;
  readonly placement: string;
}

/** Download event for a clicked link, or null when it is not a download. */
export function downloadEventFor(link: HTMLAnchorElement, pathname: string): DownloadEvent | null {
  const channel = explicitChannel(link.getAttribute(CHANNEL_ATTRIBUTE)) ?? downloadChannel(link.href);
  if (!channel) return null;
  return { channel, placement: placementFor(link, pathname) };
}

type Paq = { push: (args: unknown[]) => unknown };

function decorateStoreLink(link: HTMLAnchorElement, pathname: string): void {
  const decorated = withStoreCampaign(link.href, placementFor(link, pathname));
  if (decorated !== link.href) link.href = decorated;
}

/**
 * Wires the download event and the store campaign parameters into a page.
 * Store links are decorated up front (so the status bar shows the real
 * target) and again on click (links added later). The event is only queued
 * when Matomo is present: production, public pages (Layout.astro).
 */
export function installDownloadTracking(doc: Document = document, win: Window = window): void {
  const pathname = win.location.pathname;
  for (const link of doc.querySelectorAll<HTMLAnchorElement>('a[href]')) {
    decorateStoreLink(link, pathname);
  }
  const onActivate = (event: MouseEvent): void => {
    if (event.type === 'auxclick' && event.button !== 1) return;
    const target = event.target;
    const element = target instanceof Element ? target : target instanceof Node ? target.parentElement : null;
    const link = element?.closest<HTMLAnchorElement>('a[href]');
    if (!link) return;
    decorateStoreLink(link, pathname);
    const download = downloadEventFor(link, pathname);
    if (!download) return;
    const paq = (win as unknown as { _paq?: Paq })._paq;
    paq?.push(['trackEvent', DOWNLOAD_EVENT_CATEGORY, download.channel, download.placement]);
  };
  doc.addEventListener('click', onActivate);
  // Middle click opens a new tab without a click event.
  doc.addEventListener('auxclick', onActivate);
}
