import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../logging/app_logger.dart';
import 'mozilla_roots.dart';

final _log = AppLogger('Tls');

/// Asset key of the bundled Mozilla root store. Provenance and update steps:
/// `assets/tls/NOTICE.md`, refresh with `scripts/update-mozilla-cacert.sh`.
const String mozillaRootsAssetKey = 'assets/tls/mozilla-cacert.pem';

/// Windows only: adds the bundled Mozilla roots to the default TLS context, so
/// every `HttpClient` and Dio client of the app (they all use the default
/// context) also trusts CAs that a fresh Windows install has not fetched yet.
///
/// The system store stays active, so company proxy and antivirus roots still
/// apply. Never throws and never blocks the start: a failure is a local log
/// line only (warning level, so no Sentry event). Returns null when nothing
/// was installed. The parameters are for tests; the app passes none.
Future<MozillaRootsResult?> installBundledMozillaRoots({
  AssetBundle? bundle,
  SecurityContext? context,
  bool? isWindows,
}) async {
  if (!(isWindows ?? Platform.isWindows)) return null;
  try {
    final data = await (bundle ?? rootBundle).load(mozillaRootsAssetKey);
    final result = installMozillaRoots(
      context ?? SecurityContext.defaultContext,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    _log.info(
      'Mozilla root store: ${result.added} added, '
      '${result.rejected} already trusted or refused',
    );
    return result;
  } on Object catch (e, st) {
    _log.warning('Mozilla root store not loaded, system store only', e, st);
    return null;
  }
}
