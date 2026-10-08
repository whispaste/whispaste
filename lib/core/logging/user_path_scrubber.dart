/// Removes the OS account name from text bound for crash reports.
///
/// Home directories carry the account name (`/Users/<name>`,
/// `C:\Users\<name>`, `/home/<name>`) and reach Sentry through log
/// breadcrumbs and exception values (e.g. `FileSystemException` paths).
library;

import 'dart:io';

final _profileDir = RegExp(
  r'(/Users/|/home/|[A-Za-z]:[\\/]+Users[\\/]+)([^\\/\s]+)',
  caseSensitive: false,
);

/// Below this length a bare account name matches too much ordinary text.
const _minBareNameLength = 3;

/// Replaces [home] with `~`, the account segment of macOS/Linux/Windows
/// profile paths with `<user>`, and [userName] as a whole word with `<user>`.
///
/// [home] and [userName] default to the current process environment.
String scrubUserPaths(String input, {String? home, String? userName}) {
  home ??= _environmentHome();
  userName ??= _environmentUserName();

  var out = input;
  if (home != null && home.length > 1) {
    out = out.replaceAll(home, '~');
  }
  out = out.replaceAllMapped(_profileDir, (m) => '${m[1]}<user>');
  if (userName != null && userName.length >= _minBareNameLength) {
    out = out.replaceAll(
      RegExp(
        '(?<![A-Za-z0-9_])${RegExp.escape(userName)}(?![A-Za-z0-9_])',
        caseSensitive: false,
      ),
      '<user>',
    );
  }
  return out;
}

String? _environmentHome() {
  final env = Platform.environment;
  return Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
}

String? _environmentUserName() {
  final env = Platform.environment;
  return Platform.isWindows ? env['USERNAME'] : env['USER'];
}
