// XP-6-14: in the main window, a GNOME session without the GlobalShortcuts
// portal learns once that the hotkey works system-wide only after WhisPaste
// added it to the GNOME keyboard shortcuts, with a way to the block that
// does it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/widgets/desktop_shortcut_toast.dart';

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

Widget _page(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                showDesktopShortcutToast(context: context, ref: ref),
            child: const Text('show'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(_FakeSettings.new)],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('names the hotkey and why it is not system-wide yet', (
    tester,
  ) async {
    final container = makeContainer();
    await container.read(settingsProvider.future);
    await tester.pumpWidget(_page(container));
    await tester.tap(find.text('show'));
    await tester.pump();

    final defaults = AppSettings.defaults;
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('toast-desktop-shortcut')),
          )
          .data,
      l10n.desktopShortcutToast(
        formatHotkeyKeycap(
          defaults.hotkeyModifiers,
          defaults.hotkeyKey,
          l10n: l10n,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  });

  testWidgets('the action opens the hotkey row with the GNOME block', (
    tester,
  ) async {
    final container = makeContainer();
    await container.read(settingsProvider.future);
    await tester.pumpWidget(_page(container));
    await tester.tap(find.text('show'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('toast-desktop-shortcut-open')),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'settings');
    expect(
      container.read(settingsScrollTargetProvider),
      'general-hotkey-combo',
    );
  });
}
