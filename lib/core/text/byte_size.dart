import 'dart:io' show Platform;

import 'package:intl/intl.dart';

/// The one formatter for byte counts shown to the user: model download sizes,
/// download progress, free disk space, RAM (#1152).
///
/// **Unit decision:** the number must match what the user sees when checking
/// in the OS. Finder, Files (GNOME/KDE) and `df -H` count in steps of 1000;
/// Windows Explorer counts in steps of 1024 but still prints "MB"/"GB". So
/// [byteSizeBase] is 1024 on Windows and 1000 on macOS and Linux, and the
/// unit letters are always "KB", "MB", "GB".
///
/// Rounding: whole KB; MB with one decimal below 10, else whole; GB with one
/// decimal. The decimal separator follows [locale] (default: the app locale
/// set in `WhisPasteApp`, see `Intl.defaultLocale`). A no-break space keeps
/// number and unit on one line.
int get byteSizeBase => Platform.isWindows ? 1024 : 1000;

String formatByteSize(int bytes, {String? locale, int? base}) {
  final step = base ?? byteSizeBase;
  final loc = locale ?? Intl.getCurrentLocale();
  String num(double v, String pattern) {
    try {
      return NumberFormat(pattern, loc).format(v);
    } on Object {
      return NumberFormat(pattern, 'en').format(v);
    }
  }

  const nbsp = ' ';
  if (bytes < step) return '$bytes${nbsp}B';
  final kb = step;
  final mb = kb * step;
  final gb = mb * step;
  if (bytes < mb) return '${num(bytes / kb, '0')}${nbsp}KB';
  if (bytes < gb) {
    final v = bytes / mb;
    return '${num(v, v < 10 ? '0.0' : '0')}${nbsp}MB';
  }
  return '${num(bytes / gb, '0.0')}${nbsp}GB';
}
