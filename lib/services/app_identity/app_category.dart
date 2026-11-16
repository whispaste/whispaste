/// What kind of app a target is, for the tile shown while the real app icon
/// is unknown (the app is not installed here, or the platform found none).
///
/// The table maps the identifiers the paste host records (macOS bundle id,
/// Windows exe name, Linux WM_CLASS or Wayland app_id) to a category. It names
/// apps only to sort them; the tiles never imitate a brand.
library;

enum AppCategory {
  terminal,
  browser,
  code,
  chat,
  mail,
  notes,
  office,
  calendar,
  design,
  unknown,
}

/// Lower-case identifier → category. A trailing `*` matches a prefix
/// (`dev.warp.*` covers `dev.warp.Warp-Stable` and `dev.warp.Warp-Preview`).
const Map<String, AppCategory> _table = {
  // Terminal
  'dev.warp.*': AppCategory.terminal,
  'warp': AppCategory.terminal,
  'com.googlecode.iterm2': AppCategory.terminal,
  'com.apple.terminal': AppCategory.terminal,
  'com.mitchellh.ghostty': AppCategory.terminal,
  'ghostty': AppCategory.terminal,
  'com.github.wez.wezterm': AppCategory.terminal,
  'wezterm*': AppCategory.terminal,
  'org.alacritty': AppCategory.terminal,
  'alacritty': AppCategory.terminal,
  'net.kovidgoyal.kitty': AppCategory.terminal,
  'kitty': AppCategory.terminal,
  'co.zeit.hyper': AppCategory.terminal,
  'windowsterminal': AppCategory.terminal,
  'cmd': AppCategory.terminal,
  'powershell': AppCategory.terminal,
  'pwsh': AppCategory.terminal,
  'conhost': AppCategory.terminal,
  'org.gnome.terminal': AppCategory.terminal,
  'gnome-terminal*': AppCategory.terminal,
  'org.gnome.console': AppCategory.terminal,
  'kgx': AppCategory.terminal,
  'org.gnome.ptyxis': AppCategory.terminal,
  'ptyxis': AppCategory.terminal,
  'org.kde.konsole': AppCategory.terminal,
  'konsole': AppCategory.terminal,
  'com.gexperts.tilix': AppCategory.terminal,
  'tilix': AppCategory.terminal,
  'xterm': AppCategory.terminal,
  // Browser
  'com.apple.safari*': AppCategory.browser,
  'com.google.chrome*': AppCategory.browser,
  'chrome': AppCategory.browser,
  'google-chrome*': AppCategory.browser,
  'org.chromium.*': AppCategory.browser,
  'chromium*': AppCategory.browser,
  'org.mozilla.firefox*': AppCategory.browser,
  'firefox*': AppCategory.browser,
  // Firefox's X11 WM_CLASS res_name.
  'navigator': AppCategory.browser,
  'com.microsoft.edgemac*': AppCategory.browser,
  'msedge': AppCategory.browser,
  'microsoft-edge*': AppCategory.browser,
  'com.brave.browser*': AppCategory.browser,
  'brave*': AppCategory.browser,
  'company.thebrowser.browser': AppCategory.browser,
  'com.operasoftware.opera*': AppCategory.browser,
  'opera': AppCategory.browser,
  'com.vivaldi.vivaldi': AppCategory.browser,
  'vivaldi*': AppCategory.browser,
  'app.zen-browser.zen': AppCategory.browser,
  'org.gnome.epiphany': AppCategory.browser,
  // Code editor
  'com.microsoft.vscode*': AppCategory.code,
  'code': AppCategory.code,
  'code-insiders': AppCategory.code,
  'code-oss': AppCategory.code,
  'com.visualstudio.code*': AppCategory.code,
  'com.todesktop.230313mzl4w4u92': AppCategory.code,
  'cursor': AppCategory.code,
  'com.exafunction.windsurf': AppCategory.code,
  'windsurf': AppCategory.code,
  'com.apple.dt.xcode': AppCategory.code,
  'com.jetbrains.*': AppCategory.code,
  'jetbrains-*': AppCategory.code,
  'idea64': AppCategory.code,
  'pycharm64': AppCategory.code,
  'webstorm64': AppCategory.code,
  'phpstorm64': AppCategory.code,
  'rider64': AppCategory.code,
  'clion64': AppCategory.code,
  'goland64': AppCategory.code,
  'studio64': AppCategory.code,
  'com.google.android.studio': AppCategory.code,
  'dev.zed.zed*': AppCategory.code,
  'zed': AppCategory.code,
  'com.sublimetext.*': AppCategory.code,
  'sublime_text': AppCategory.code,
  'devenv': AppCategory.code,
  'org.kde.kate': AppCategory.code,
  // Chat and messenger
  'com.tinyspeck.slackmacgap': AppCategory.chat,
  'slack': AppCategory.chat,
  'com.hnc.discord': AppCategory.chat,
  'discord': AppCategory.chat,
  'ru.keepcoder.telegram': AppCategory.chat,
  'org.telegram.desktop': AppCategory.chat,
  'telegram*': AppCategory.chat,
  'net.whatsapp.whatsapp': AppCategory.chat,
  'whatsapp*': AppCategory.chat,
  'com.microsoft.teams*': AppCategory.chat,
  'ms-teams': AppCategory.chat,
  'teams': AppCategory.chat,
  'us.zoom.xos': AppCategory.chat,
  'zoom': AppCategory.chat,
  'org.whispersystems.signal-desktop': AppCategory.chat,
  'signal*': AppCategory.chat,
  'com.apple.mobilesms': AppCategory.chat,
  'im.riot.riot': AppCategory.chat,
  'element': AppCategory.chat,
  // Mail
  'com.apple.mail': AppCategory.mail,
  'com.microsoft.outlook': AppCategory.mail,
  'outlook': AppCategory.mail,
  'olk': AppCategory.mail,
  'org.mozilla.thunderbird': AppCategory.mail,
  'thunderbird*': AppCategory.mail,
  'com.readdle.smartemail-mac': AppCategory.mail,
  'org.gnome.evolution': AppCategory.mail,
  'evolution': AppCategory.mail,
  'org.kde.kmail2': AppCategory.mail,
  // Notes and plain documents
  'com.apple.notes': AppCategory.notes,
  'com.apple.textedit': AppCategory.notes,
  'notion.id': AppCategory.notes,
  'notion': AppCategory.notes,
  'md.obsidian': AppCategory.notes,
  'obsidian': AppCategory.notes,
  'net.shinyfrog.bear': AppCategory.notes,
  'com.microsoft.onenote*': AppCategory.notes,
  'onenote': AppCategory.notes,
  'com.evernote.*': AppCategory.notes,
  'evernote': AppCategory.notes,
  'com.logseq.logseq': AppCategory.notes,
  'logseq': AppCategory.notes,
  'abnerworks.typora': AppCategory.notes,
  'typora': AppCategory.notes,
  'notepad': AppCategory.notes,
  'notepad++': AppCategory.notes,
  'org.gnome.texteditor': AppCategory.notes,
  'gnome-text-editor': AppCategory.notes,
  'org.gnome.gedit': AppCategory.notes,
  'gedit': AppCategory.notes,
  // Office
  'com.microsoft.word': AppCategory.office,
  'winword': AppCategory.office,
  'com.microsoft.excel': AppCategory.office,
  'excel': AppCategory.office,
  'com.microsoft.powerpoint': AppCategory.office,
  'powerpnt': AppCategory.office,
  'com.apple.iwork.*': AppCategory.office,
  'org.libreoffice.*': AppCategory.office,
  'libreoffice*': AppCategory.office,
  'soffice*': AppCategory.office,
  // Calendar
  'com.apple.ical': AppCategory.calendar,
  'com.flexibits.fantastical2.mac': AppCategory.calendar,
  'org.gnome.calendar': AppCategory.calendar,
  'gnome-calendar': AppCategory.calendar,
  'org.kde.merkuro.calendar': AppCategory.calendar,
  // Design
  'com.figma.desktop': AppCategory.design,
  'figma*': AppCategory.design,
  'com.bohemiancoding.sketch3': AppCategory.design,
  'com.adobe.*': AppCategory.design,
  'photoshop': AppCategory.design,
  'illustrator': AppCategory.design,
  'indesign': AppCategory.design,
  'com.seriflabs.*': AppCategory.design,
  'org.inkscape.inkscape': AppCategory.design,
  'inkscape': AppCategory.design,
  'org.gimp.gimp': AppCategory.design,
  'gimp*': AppCategory.design,
  'org.kde.krita': AppCategory.design,
  'krita': AppCategory.design,
};

final List<MapEntry<String, AppCategory>> _prefixes = [
  for (final e in _table.entries)
    if (e.key.endsWith('*'))
      MapEntry(e.key.substring(0, e.key.length - 1), e.value),
]..sort((a, b) => b.key.length.compareTo(a.key.length));

/// The category of [identifier]: exact match first, then the longest prefix.
/// Case and a trailing `.exe` do not matter. Unlisted apps are
/// [AppCategory.unknown].
AppCategory appCategoryFor(String identifier) {
  var id = identifier.trim().toLowerCase();
  if (id.endsWith('.exe')) id = id.substring(0, id.length - 4);
  if (id.isEmpty) return AppCategory.unknown;
  final exact = _table[id];
  if (exact != null) return exact;
  for (final prefix in _prefixes) {
    if (id.startsWith(prefix.key)) return prefix.value;
  }
  return AppCategory.unknown;
}
