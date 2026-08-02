// Standalone helper process for cross-process single-instance lock tests.
//
// Deliberately does NOT import `package:whispaste/...` — pulling in
// SingleInstanceService drags in AppLogger -> sentry_flutter -> dart:ui,
// which a plain `dart run` can't resolve. So this duplicates the three-line
// lock primitive under test (open append, non-blocking exclusive lock,
// catch FileSystemException) rather than reusing the real implementation.
//
// Usage: dart run single_instance_probe.dart <lockDir> [holdMillis]
//
// Prints exactly one line — PRIMARY or SECONDARY — then, if PRIMARY and
// [holdMillis] was given, holds the lock for that long before exiting (lock
// release on exit is automatic; the OS drops it when the process dies).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final dir = args[0];
  final holdMillis = args.length > 1 ? int.parse(args[1]) : 0;

  await Directory(dir).create(recursive: true);
  final raf = await File(
    p.join(dir, 'instance.lock'),
  ).open(mode: FileMode.append);

  try {
    await raf.lock(FileLock.exclusive);
  } on FileSystemException {
    await raf.close();
    await File(
      p.join(dir, 'focus.signal'),
    ).writeAsString(DateTime.now().toIso8601String(), flush: true);
    // ignore: avoid_print
    print('SECONDARY');
    return;
  }

  // ignore: avoid_print
  print('PRIMARY');
  if (holdMillis > 0) {
    await Future<void>.delayed(Duration(milliseconds: holdMillis));
  }
  await raf.unlock();
  await raf.close();
}
