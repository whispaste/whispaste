export type Platform = 'windows' | 'macos' | 'unknown';

/** Reads the OS that was detected by the inline head script and stored in data-os. */
export function detectPlatform(): Platform {
  if (typeof document === 'undefined') return 'unknown';
  const os = document.documentElement.dataset.os;
  if (os === 'windows') return 'windows';
  if (os === 'macos') return 'macos';
  return 'unknown';
}
