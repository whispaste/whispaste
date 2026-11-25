import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import 'path_service.dart' as paths;

/// Each Explorer invocation has its own atomic request. Unlike a focus signal,
/// consecutive imports must not overwrite or debounce one another.
class FileImportInbox {
  FileImportInbox({Directory? directory})
    : directory =
          directory ??
          Directory(p.join(paths.appDataDir(), 'single_instance', 'imports'));

  final Directory directory;
  final _log = AppLogger('FileImportInbox');
  Timer? _timer;
  bool _reading = false;
  bool _closed = false;

  static List<String> arguments(List<String> args) {
    if (args.isEmpty || args.first != '--import-files') return [];
    return args.skip(1).where(p.isAbsolute).toList();
  }

  Future<void> enqueue(List<String> files) async {
    if (files.isEmpty) return;
    await directory.create(recursive: true);
    final request = await directory.createTemp('request-');
    final pending = File(p.join(request.path, 'pending.json'));
    await pending.writeAsString(jsonEncode(files), flush: true);
    await pending.rename(p.join(request.path, 'ready.json'));
  }

  /// The receiver synchronously hands files to the import queue; it must not
  /// wait for transcription. Polling also covers filesystem watcher gaps.
  void start(void Function(List<String>) receive) {
    _closed = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      unawaited(drain(receive));
    });
    unawaited(drain(receive));
  }

  Future<void> drain(void Function(List<String>) receive) async {
    if (_closed || _reading) return;
    _reading = true;
    try {
      if (!await directory.exists()) return;
      final requests = await directory
          .list()
          .where((e) => e is Directory)
          .toList();
      requests.sort((a, b) => a.path.compareTo(b.path));
      for (final request in requests) {
        if (_closed) return;
        final ready = File(p.join(request.path, 'ready.json'));
        if (!await ready.exists()) continue;
        try {
          final value = jsonDecode(await ready.readAsString());
          if (value is! List ||
              value.any((e) => e is! String || !p.isAbsolute(e))) {
            throw const FormatException('Invalid file import request');
          }
          receive(value.cast<String>());
          await request.delete(recursive: true);
        } on FormatException {
          _log.warning('Discarding malformed file import request');
          await request.delete(recursive: true);
        }
      }
    } on Object catch (e) {
      _log.warning('Reading file import requests failed', e);
    } finally {
      _reading = false;
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}
