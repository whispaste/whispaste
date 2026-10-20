// XP-5-09: when another app holds the configured hotkey, the safe default
// takes over. The user has to learn that once, with the combination that now
// starts a recording and a way to change it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/ltr_isolate.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/hotkey_fallback_toast.dart';

class _RecordingAttention extends SystemAttentionService {
  _RecordingAttention(super.ref);

  final calls = <(AttentionKind, String, String)>[];

  @override
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    calls.add((kind, title, body));
  }
}

class _FakeSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

Widget _page(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () =>
                showHotkeyFallbackToast(context: context, ref: ref),
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

  testWidgets('names the taken and the active combination', (tester) async {
    final container = makeContainer();
    await container.read(settingsProvider.future);
    await tester.pumpWidget(_page(container));
    await tester.tap(find.text('show'));
    await tester.pump();

    final defaults = AppSettings.defaults;
    final message = l10n.hotkeyFallbackActive(
      ltrIsolate(
        formatHotkeyKeycap(
          defaults.hotkeyModifiers,
          defaults.hotkeyKey,
          l10n: l10n,
        ),
      ),
      ltrIsolate(
        formatHotkeyKeycap(
          safeDefaultHotkeyModifiers,
          safeDefaultHotkeyKey,
          l10n: l10n,
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('toast-hotkey-fallback')),
          )
          .data,
      message,
    );
    // Let the toast time out so no timer outlives the test.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  });

  // UIA-VIS-08: in Hebrew the Latin key names keep their order and do not
  // break apart mid-combination; each keycap is an LTR isolate.
  testWidgets('each combination is an LTR isolate in Hebrew', (tester) async {
    final container = makeContainer();
    await container.read(settingsProvider.future);
    await tester.pumpWidget(_page(container, locale: const Locale('he')));
    await tester.tap(find.text('show'));
    await tester.pump();

    final he = await L10n.delegate.load(const Locale('he'));
    final text = tester
        .widget<Text>(
          find.byKey(const ValueKey<String>('toast-hotkey-fallback')),
        )
        .data!;
    for (final keycap in [
      formatHotkeyKeycap(
        AppSettings.defaults.hotkeyModifiers,
        AppSettings.defaults.hotkeyKey,
        l10n: he,
      ),
      formatHotkeyKeycap(
        safeDefaultHotkeyModifiers,
        safeDefaultHotkeyKey,
        l10n: he,
      ),
    ]) {
      expect(text, contains(ltrIsolate(keycap)));
    }
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  });

  testWidgets('the action opens the hotkey row in settings', (tester) async {
    final container = makeContainer();
    await container.read(settingsProvider.future);
    await tester.pumpWidget(_page(container));
    await tester.tap(find.text('show'));
    // Past the slide-in, so the tap lands on the button.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tester.tap(
      find.byKey(const ValueKey<String>('toast-hotkey-fallback-change')),
    );
    await tester.pumpAndSettle();

    expect(container.read(activePageProvider), 'settings');
    expect(
      container.read(settingsScrollTargetProvider),
      'general-hotkey-combo',
    );
  });

  group('notifyHotkeyFallbackIfHidden', () {
    // Start minimised to the tray is the default, and a toast in a hidden
    // window reaches nobody.
    Future<_RecordingAttention> run(
      WidgetTester tester, {
      required bool hidden,
    }) async {
      late _RecordingAttention attention;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_FakeSettings.new),
          mainWindowHiddenProvider.overrideWithValue(() async => hidden),
          systemAttentionServiceProvider.overrideWith(
            (ref) => attention = _RecordingAttention(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              notifyHotkeyFallbackIfHidden(ref: ref, l10n: l10n);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      return attention;
    }

    testWidgets('sends the message as a notification while hidden', (
      tester,
    ) async {
      final attention = await run(tester, hidden: true);

      expect(attention.calls, hasLength(1));
      final (kind, title, body) = attention.calls.single;
      expect(kind, AttentionKind.hotkeyFallback);
      expect(title, l10n.notificationHotkeyFallbackTitle);
      expect(
        body,
        l10n.hotkeyFallbackActive(
          ltrIsolate(
            formatHotkeyKeycap(
              AppSettings.defaults.hotkeyModifiers,
              AppSettings.defaults.hotkeyKey,
              l10n: l10n,
            ),
          ),
          ltrIsolate(
            formatHotkeyKeycap(
              safeDefaultHotkeyModifiers,
              safeDefaultHotkeyKey,
              l10n: l10n,
            ),
          ),
        ),
      );
    });

    testWidgets('stays quiet while the window, and so the toast, is visible', (
      tester,
    ) async {
      final attention = await run(tester, hidden: false);

      expect(attention.calls, isEmpty);
    });
  });
}
