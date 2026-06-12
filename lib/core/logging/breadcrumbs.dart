/// Breadcrumb ring buffer — shared between [app_logger.dart] and
/// [crash_reporter.dart] to break the circular import between those two files.
///
/// Both files import THIS file; neither imports the other for this purpose.
library;

import 'dart:collection';

// ---------------------------------------------------------------------------
// Breadcrumb ring buffer
// ---------------------------------------------------------------------------

/// Breadcrumb ring buffer — last N log lines kept for crash context.
class BreadcrumbRing {
  BreadcrumbRing(this._capacity);
  final int _capacity;
  final _buf = Queue<String>();

  void add(String line) {
    if (_buf.length >= _capacity) _buf.removeFirst();
    _buf.add(line);
  }

  List<String> get recent => _buf.toList();
}

/// Shared ring buffer instance — written by [configureLogging] in
/// [app_logger.dart], read by [CrashReporter] in [crash_reporter.dart].
final breadcrumbRing = BreadcrumbRing(30);

/// Returns the most recent log lines for crash report context.
List<String> getRecentBreadcrumbs() => breadcrumbRing.recent;
