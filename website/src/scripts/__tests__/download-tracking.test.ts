// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import {
  downloadChannel,
  installDownloadTracking,
  placementFor,
  placementForPath,
  withStoreCampaign,
} from '../download-tracking';
import {
  LINUX_APPIMAGE_URL,
  LINUX_DEB_URL,
  MACOS_DMG_URL,
  MAC_APP_STORE_REVIEW_URL,
  MAC_APP_STORE_URL,
  MS_STORE_REVIEW_URL,
  MS_STORE_URL,
  WINDOWS_SETUP_URL,
  DIAGNOSE_WINDOWS_URL,
  GITHUB_REPO_URL,
} from '../../data/platforms';

const RELEASE = 'https://github.com/whispaste/whispaste/releases';

describe('downloadChannel', () => {
  it.each([
    [MS_STORE_URL, 'store-ms'],
    [`${MS_STORE_URL}?cid=web-hero`, 'store-ms'],
    [MAC_APP_STORE_URL, 'store-mac'],
    ['https://apps.apple.com/de/app/whispaste/id6795319409?ct=web-hero', 'store-mac'],
    [WINDOWS_SETUP_URL, 'github-exe'],
    [`${RELEASE}/download/v1.5.2/WhisPaste-1.5.2-windows-x64.zip`, 'github-portable'],
    [MACOS_DMG_URL, 'github-dmg'],
    [LINUX_APPIMAGE_URL, 'appimage'],
    [LINUX_DEB_URL, 'deb'],
    [`${RELEASE}/download/v1.5.2/WhisPaste-1.5.2-linux-x64.tar.gz`, 'linux-tar'],
    [`${RELEASE}/download/v1.5.2/whispaste.x86_64.rpm`, 'rpm'],
    ['https://flathub.org/apps/io.github.whispaste.WhisPaste', 'flatpak'],
    ['https://snapcraft.io/whispaste', 'snap'],
    [RELEASE, 'github-releases'],
    [`${RELEASE}/tag/v1.4.2`, 'github-releases'],
  ])('%s → %s', (href, channel) => {
    expect(downloadChannel(href)).toBe(channel);
  });

  it.each([
    MS_STORE_REVIEW_URL,
    MAC_APP_STORE_REVIEW_URL,
    DIAGNOSE_WINDOWS_URL,
    `${RELEASE}/download/v1.5.2/WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-windows-x64.zip`,
    GITHUB_REPO_URL,
    `${GITHUB_REPO_URL}/blob/main/LICENSE`,
    'https://apps.microsoft.com/detail/9nblggh4r32n',
    '/download/',
    'not a url ::',
  ])('%s is not a download', (href) => {
    expect(downloadChannel(href)).toBeNull();
  });
});

describe('placementForPath', () => {
  it.each([
    ['/', 'home'],
    ['/en/', 'home'],
    ['/download/', 'download-page'],
    ['/ru/download/', 'download-page'],
    ['/whisper-desktop/', 'whisper-desktop'],
    ['/zh/whisper-desktop/', 'whisper-desktop'],
    ['/vergleich/whispaste-vs-system-spracheingabe/', 'comparison'],
    ['/en/comparison/voice-input-tool-alternatives/', 'comparison'],
    ['/linux-spracherkennung/', 'linux-speech-to-text'],
    ['/en/blog/neu-in-whispaste-1-5/', 'blog'],
  ])('%s → %s', (path, placement) => {
    expect(placementForPath(path)).toBe(placement);
  });
});

describe('placementFor', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('prefers the nearest marked surface over the page', () => {
    document.body.innerHTML = `<section data-download-placement="pricing"><div data-download-placement="Hero CTA"><a id="a" href="${MS_STORE_URL}">x</a></div></section>`;
    expect(placementFor(document.getElementById('a')!, '/en/')).toBe('hero-cta');
  });

  it('falls back to the page', () => {
    document.body.innerHTML = `<a id="a" href="${MS_STORE_URL}">x</a>`;
    expect(placementFor(document.getElementById('a')!, '/en/download/')).toBe('download-page');
  });
});

describe('withStoreCampaign', () => {
  it('adds cid to Microsoft Store links', () => {
    expect(withStoreCampaign(MS_STORE_URL, 'hero')).toBe(
      'https://apps.microsoft.com/detail/9p22jvkrq2v0?cid=web-hero',
    );
  });

  it('adds ct (no pt) to Mac App Store links', () => {
    const href = withStoreCampaign(MAC_APP_STORE_URL, 'download-page');
    expect(href).toBe('https://apps.apple.com/app/id6795319409?ct=web-download-page');
    expect(new URL(href).searchParams.has('pt')).toBe(false);
  });

  it('keeps an existing campaign and leaves other links alone', () => {
    expect(withStoreCampaign(`${MS_STORE_URL}?cid=yt-promo`, 'hero')).toBe(`${MS_STORE_URL}?cid=yt-promo`);
    expect(withStoreCampaign(MS_STORE_REVIEW_URL, 'hero')).toBe(MS_STORE_REVIEW_URL);
    expect(withStoreCampaign(WINDOWS_SETUP_URL, 'hero')).toBe(WINDOWS_SETUP_URL);
  });

  it('caps the campaign value at Apple’s 40 characters', () => {
    const ct = new URL(withStoreCampaign(MAC_APP_STORE_URL, 'x'.repeat(80))).searchParams.get('ct')!;
    expect(ct.length).toBeLessThanOrEqual(40);
  });
});

describe('installDownloadTracking', () => {
  it('decorates store links and queues one event per download click', () => {
    document.body.innerHTML = `
      <div data-download-placement="hero"><a id="store" href="${MS_STORE_URL}"><span id="inner">Store</span></a></div>
      <a id="exe" href="${WINDOWS_SETUP_URL}">exe</a>
      <a id="src" href="${GITHUB_REPO_URL}" data-download-channel="source">src</a>
      <a id="nav" href="${GITHUB_REPO_URL}">nav</a>`;
    const pushed: unknown[][] = [];
    (window as unknown as { _paq: { push: (a: unknown[]) => void } })._paq = { push: (a) => pushed.push(a) };
    window.history.replaceState(null, '', '/en/download/');
    installDownloadTracking(document, window);
    for (const a of document.querySelectorAll('a')) a.addEventListener('click', (e) => e.preventDefault());

    expect(document.querySelector<HTMLAnchorElement>('#store')!.href).toBe(`${MS_STORE_URL}?cid=web-hero`);
    for (const id of ['inner', 'exe', 'src', 'nav']) document.getElementById(id)!.click();

    expect(pushed).toEqual([
      ['trackEvent', 'Download', 'store-ms', 'hero'],
      ['trackEvent', 'Download', 'github-exe', 'download-page'],
      ['trackEvent', 'Download', 'source', 'download-page'],
    ]);
  });
});

describe('Matomo download classification of the AppImage', () => {
  // Same pattern matomo.js builds from its extension list (getLinkType):
  // with EXTRA_DOWNLOAD_EXTENSIONS added, the AppImage link is a download,
  // not an outlink.
  it('matches the AppImage release URL', async () => {
    const { EXTRA_DOWNLOAD_EXTENSIONS } = await import('../download-tracking');
    const pattern = new RegExp(`\\.(${EXTRA_DOWNLOAD_EXTENSIONS.join('|')})([?&#]|$)`, 'i');
    expect(pattern.test(LINUX_APPIMAGE_URL)).toBe(true);
  });
});
