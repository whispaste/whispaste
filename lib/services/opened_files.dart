/// Files the system asks WhisPaste to open (#1684): the file manager's
/// "Transcribe with WhisPaste" entry and "Open With".
///
/// - Windows (NSIS verb, MSIX verb) starts `whispaste.exe "<path>"`, one
///   process per selected file.
/// - Linux starts `whispaste %U`: the file manager hands `file://` URIs (or
///   plain paths), all selected files in one process.
/// - macOS never starts a second process; AppKit hands the running app the
///   file URLs (`application(_:open:)`, see [SingleInstanceService.openUrls]).
///
/// Every path ends in the normal file transcription (`importAudioFiles`),
/// which refuses a missing file or an unsupported type with a notice.
library;

import 'package:path/path.dart' as p;

import 'app_link.dart';

/// The file paths among the launch arguments. Flags (`--toggle`, `-x`) and
/// links of other schemes, `whispaste://` included, are not files. A
/// relative path (a terminal start, `whispaste memo.mp3`) is resolved
/// against the working folder. [context] picks the path style (tests).
List<String> openedFilesFromArgs(List<String> args, {p.Context? context}) {
  final ctx = context ?? p.context;
  final files = <String>[];
  for (final arg in args) {
    final path = openedFileFromArg(arg, context: ctx);
    if (path != null) files.add(path);
  }
  return files;
}

/// One launch argument or opened URL as a file path, or null when it is no
/// file: a flag, an app link or a URL of another scheme.
String? openedFileFromArg(String arg, {p.Context? context}) {
  final ctx = context ?? p.context;
  final value = arg.trim();
  if (value.isEmpty || value.startsWith('-')) return null;
  if (AppLink.parse(value) != AppLink.none) return null;
  final windows = ctx.style == p.Style.windows;
  final uri = Uri.tryParse(value);
  // A one-letter scheme is a Windows drive (`C:\…`), not a URL.
  if (uri != null && uri.scheme.length > 1) {
    if (uri.scheme.toLowerCase() != 'file') return null;
    try {
      return ctx.normalize(uri.toFilePath(windows: windows));
    } on UnsupportedError {
      // A file URL with a host other than localhost (a network share URL
      // on POSIX): not a path this system can open.
      return null;
    }
  }
  return ctx.normalize(ctx.absolute(value));
}
