/// Opens a model folder in the system file manager (#1513): the last way out
/// of a download that keeps failing is to put the file there by hand
/// (manual, chapter "Install a speech model manually").
library;

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('ModelFolder');

/// Opens [path] in Finder, Explorer or the Linux file manager, creating it
/// first so a fresh install has a folder to drop the file into. Returns
/// false when the system could not open it.
Future<bool> openModelFolder(String path) async {
  try {
    await Directory(path).create(recursive: true);
    return await launchUrl(Uri.directory(path));
  } on Object catch (e) {
    _log.warning('Could not open model folder $path', e);
    return false;
  }
}
