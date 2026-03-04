export function toggleTheme() {
  const html = document.documentElement;
  const isDark = !html.classList.contains('light');
  if (isDark) {
    html.classList.add('light');
    localStorage.setItem('whispaste-theme', 'light');
  } else {
    html.classList.remove('light');
    localStorage.setItem('whispaste-theme', 'dark');
  }
  updateThemeIcon();
}

export function updateThemeIcon() {
  const isLight = document.documentElement.classList.contains('light');
  const icon = document.getElementById('themeIcon');
  if (icon) {
    icon.innerHTML = isLight
      ? '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>'
      : '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>';
  }
  const lightSrc = '/whispaste/app-icon-light.png';
  const darkSrc = '/whispaste/app-icon-dark.png';
  const src = isLight ? lightSrc : darkSrc;
  ['navLogo', 'heroLogo', 'footerLogo'].forEach(id => {
    const el = document.getElementById(id) as HTMLImageElement | null;
    if (el) el.src = src;
  });
  document.querySelectorAll<HTMLImageElement>('.mockup-app-icon').forEach(el => { el.src = src; });
}

// Expose globally for onclick handlers
(window as any).toggleTheme = toggleTheme;
