/// Migration tests proving that old configs containing removed settings keys
/// load without errors and fall back silently to defaults.
///
/// Issue 11 removed the following overlay/button settings:
///   - floating_button_size  (size picker → fixed 56 dp design token)
///   - floating_button_opacity  (removed earlier, confirmed absent from map)
///   - floating_overlay_opacity  (removed earlier, confirmed absent from map)
///   - settingsOverlayAutoHide* keys  (no persistence, L10n-only dead keys)
///
/// Contract under test: [AppSettings.fromStorageMap] ignores unknown keys and
/// never throws. Old SQLite rows with the removed keys simply leave the
/// corresponding field at its default.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';

void main() {
  group('Issue-11 removed-keys migration', () {
    test(
      'config with floating_button_size loads without error and ignores the key',
      () {
        final map = {
          'floating_button_size': 'large',
          'show_floating_button': 'true',
        };
        final settings = AppSettings.fromStorageMap(map);
        expect(settings.showFloatingButton, isTrue);
        // No floatingButtonSize field on AppSettings any more.
        // Verify the overlay section round-trips cleanly without it.
        expect(
          settings.toStorageMap().containsKey('floating_button_size'),
          isFalse,
        );
      },
    );

    test('config with floating_button_opacity loads without error', () {
      final map = {'floating_button_opacity': '0.8'};
      expect(() => AppSettings.fromStorageMap(map), returnsNormally);
      final settings = AppSettings.fromStorageMap(map);
      expect(
        settings.toStorageMap().containsKey('floating_button_opacity'),
        isFalse,
      );
    });

    test('config with floating_overlay_opacity loads without error', () {
      final map = {'floating_overlay_opacity': '0.7'};
      expect(() => AppSettings.fromStorageMap(map), returnsNormally);
      final settings = AppSettings.fromStorageMap(map);
      expect(
        settings.toStorageMap().containsKey('floating_overlay_opacity'),
        isFalse,
      );
    });

    test('config with all removed overlay keys loads without error and applies '
        'surviving overlay fields correctly', () {
      final map = {
        // Removed in issue 11 — should be silently ignored.
        'floating_button_size': 'small',
        'floating_button_opacity': '0.5',
        'floating_overlay_opacity': '0.6',
        // Still valid — must survive.
        'show_overlay': 'true',
        'overlay_mode': 'floating',
        'overlay_start_position': 'bottom-center',
        'overlay_size': 'compact',
        'show_floating_button': 'true',
      };

      final settings = AppSettings.fromStorageMap(map);

      // Surviving fields
      expect(settings.showOverlay, isTrue);
      expect(settings.overlayMode, 'floating');
      expect(settings.overlayStartPosition, 'bottom-center');
      expect(settings.overlaySize, 'compact');
      expect(settings.showFloatingButton, isTrue);

      // Removed keys must not appear in the written-back map.
      final written = settings.toStorageMap();
      expect(written.containsKey('floating_button_size'), isFalse);
      expect(written.containsKey('floating_button_opacity'), isFalse);
      expect(written.containsKey('floating_overlay_opacity'), isFalse);
    });

    test('empty config (blank DB) loads to overlay defaults without error', () {
      expect(() => AppSettings.fromStorageMap({}), returnsNormally);
      final s = AppSettings.fromStorageMap({});
      expect(s.showOverlay, AppSettings.defaults.showOverlay);
      expect(s.showFloatingButton, AppSettings.defaults.showFloatingButton);
    });
  });
}
