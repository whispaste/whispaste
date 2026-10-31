/// Runs the real `com.whispaste.app_identity` host against apps every lab
/// machine has: Finder on macOS, Explorer on Windows (always running, so the
/// lookup goes through the process list), Files on Ubuntu (by app_id and by
/// its Exec program, the WM_CLASS route). Each must answer a name and a PNG;
/// an unknown identifier must answer neither.
/// Run with `flutter test integration_test/app_identity_channel_test.dart -d`
/// and the target macos, linux or windows.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/services/app_identity/app_identity_service.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47];

List<String> get _knownApps {
  if (Platform.isMacOS) return ['com.apple.finder'];
  if (Platform.isWindows) return ['explorer', 'explorer.exe'];
  return ['org.gnome.Nautilus', 'nautilus'];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final id in _knownApps) {
    testWidgets('resolves $id to a name and a PNG icon', (tester) async {
      final info = await AppIdentityChannel.lookup(id, appIconPixelSize);
      expect(info, isNotNull, reason: 'no answer for $id');
      expect(info!.name, isNotEmpty);
      final png = info.iconPng;
      expect(png, isNotNull, reason: 'no icon for $id');
      expect(png!.take(4), _pngMagic);
      // ignore: avoid_print
      print('APP-IDENTITY $id -> "${info.name}" (${png.length} bytes)');
    });
  }

  testWidgets('an unknown identifier answers nothing', (tester) async {
    final info = await AppIdentityChannel.lookup(
      'com.example.not-installed-anywhere',
      appIconPixelSize,
    );
    expect(info, isNull);
  });
}
