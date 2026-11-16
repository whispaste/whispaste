/// Removes the OS account name from text bound for crash reports.
///
/// Home directories carry the account name (`/Users/<name>`,
/// `C:\Users\<name>`, `/home/<name>`) and reach Sentry through log
/// breadcrumbs and exception values (e.g. `FileSystemException` paths).
library;

import 'dart:io';

/// The account segment runs to the next separator, spaces, commas and
/// semicolons included (`Max Muster`, `Muster, Max`, `a;b`): when in doubt,
/// more is redacted. Only a colon or a quote followed by whitespace or the
/// end ends it early. Neither occurs in Windows account names, and they are
/// how `FileSystemException` and most error texts follow a path.
final _profileDir = RegExp(
  r'(/Users/|/home/|[A-Za-z]:[\\/]+Users[\\/]+)'
  r'((?:[^\\/\r\n:"\x27]|[:"\x27](?!\s|$))+)',
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
    // Match whole path segments only: a home of `C:\Users\silvi` must not
    // rewrite the prefix of `C:\Users\me`.
    out = out.replaceAll(RegExp('${RegExp.escape(home)}(?![A-Za-z0-9_])'), '~');
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

/// Returns a copy of [values] with [scrubUserPaths] applied to every String
/// leaf, recursing into nested maps and lists. Keys and non-string values
/// are kept as they are.
Map<String, dynamic> scrubUserPathsInMap(
  Map<String, dynamic> values, {
  String? home,
  String? userName,
}) {
  return {
    for (final entry in values.entries)
      entry.key: _scrubValue(entry.value, home: home, userName: userName),
  };
}

Object? _scrubValue(Object? value, {String? home, String? userName}) {
  return switch (value) {
    String() => scrubUserPaths(value, home: home, userName: userName),
    Map() => scrubUserPathsInMap(
      value.cast<String, dynamic>(),
      home: home,
      userName: userName,
    ),
    List() => [
      for (final item in value)
        _scrubValue(item, home: home, userName: userName),
    ],
    _ => value,
  };
}
