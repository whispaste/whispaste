import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/ltr_isolate.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/features/settings/sections/recording_sections.dart';

import '../../fixtures/test_helpers.dart';

import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

import '../../fixtures/record_device_listing_stub.dart';

late L10n l10n;

void main() {
  stubRecordDeviceListing();
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('KeyboardShortcutSection', () {
    testWidgets('renders Hold to Record toggle inside the hotkey block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          // Scrollbar gepumpt, seit die Sektion drei Hotkey-Einträge trägt:
          // sie ist damit höher als das 800x600-Testfenster, in der App aber
          // ohnehin Teil einer scrollenden Einstellungsseite.
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsOneWidget);
    });

    testWidgets('the Hold to Record row announces its toggled state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(
                  audioInput: AudioInputSettings(pushToTalk: true),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Every other toggle row in Settings carries hasToggledState; this one
      // was the exception until the audit. Skipped where the platform cannot
      // do key-up at all, because then the row genuinely has no state.
      final supportsKeyUp = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(hotkeyServiceProvider.notifier).supportsKeyUp;
      final row = tester.getSemantics(
        find.ancestor(
          of: find.text(l10n.settingsHoldToRecord),
          matching: find.byType(WpSettingsRow),
        ),
      );
      // Both branches are asserted on purpose: a bare `if (supportsKeyUp)`
      // would pass having checked nothing on a host without key-up support,
      // which is the same hollow shape this audit twice had to repair.
      if (supportsKeyUp) {
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint: l10n.holdToRecordExplained,
            hasToggledState: true,
            isToggled: true,
          ),
        );
      } else {
        // No key-up means no push-to-talk, so the row must claim no state
        // rather than a state its disabled switch would never accept.
        expect(
          row,
          matchesSemantics(
            label: l10n.settingsHoldToRecord,
            hint:
                '${l10n.onboardingTriggerModeToggleHint}\n'
                '${pushToTalkUnavailableMessage(l10n, operatingSystem: 'other')}',
          ),
        );
      }
      handle.dispose();
    });

    testWidgets('a disabled hotkey takes the Change-hotkey button out of the '
        'tab order, not just out of the mouse\'s reach', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: KeyboardShortcutSection()),
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettings(
                const AppSettings(hotkey: HotkeySettings(hotkeyEnabled: false)),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The row is still rendered (dimmed to 40%), so finding it is not the
      // test — reaching it with the keyboard is.
      //
      // `.first` seit dem Schnellnotiz-Hotkey: die Sektion trägt jetzt zwei
      // „Ändern"-Buttons, und dieser Test meint den des Haupt-Hotkeys.
      final button = find.text(l10n.settingsChangeHotkey).first;
      expect(button, findsOneWidget);

      // Behavioural, not structural: ExcludeFocus leaves the descendant Focus
      // widgets' own canRequestFocus untouched and blocks them from the node
      // tree instead, so asking the node to take focus is the only probe that
      // actually answers the question.
      final node = Focus.of(tester.element(button));
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'Tab must not land on a control for a switched-off hotkey',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Schnellnotiz-Hotkey — der zweite, nachgeordnete Eintrag
  // ---------------------------------------------------------------------------

  group('KeyboardShortcutSection — safe-default fallback (XP-5-09)', () {
    Widget subject({required bool fallback}) => makeTestable(
      const SingleChildScrollView(child: KeyboardShortcutSection()),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettings(AppSettings.defaults),
        ),
        globalHotkeyFallbackActiveProvider.overrideWith(
          () => _FakeFallback(fallback),
        ),
      ],
    );

    HotkeyDisplay mainDisplay(WidgetTester tester) => tester.widget(
      find
          .descendant(
            of: find.byKey(const ValueKey('settings-row-general-hotkey-combo')),
            matching: find.byType(HotkeyDisplay),
          )
          .first,
    );

    testWidgets('shows the active fallback and says why', (tester) async {
      await tester.pumpWidget(subject(fallback: true));
      await tester.pumpAndSettle();

      final display = mainDisplay(tester);
      expect(display.hotkeyKey, safeDefaultHotkeyKey);
      expect(display.hotkeyModifiers, safeDefaultHotkeyModifiers);
      final defaults = AppSettings.defaults;
      expect(
        find.text(
          // Both combinations are LTR isolates, as in the toast (UIA-VIS-08).
          l10n.hotkeyFallbackActive(
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
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('mainHotkeyFallbackNotice')), findsOneWidget);
    });

    testWidgets('without a fallback the configured hotkey shows, no notice', (
      tester,
    ) async {
      await tester.pumpWidget(subject(fallback: false));
      await tester.pumpAndSettle();

      expect(mainDisplay(tester).hotkeyKey, AppSettings.defaults.hotkeyKey);
      expect(find.byKey(const Key('mainHotkeyFallbackNotice')), findsNothing);
    });
  });

  group('KeyboardShortcutSection — hold-or-tap (ticket catchup/07)', () {
    const toggleKey = Key('holdOrTapToggle');

    Widget subject({
      required bool supportsKeyUp,
      required bool pushToTalk,
      bool holdOrTap = false,
    }) {
      final svc = HotkeyService()
        ..injectRegistrar(_KeyUpRegistrar(supportsKeyUp: supportsKeyUp))
        // Pin the monitor so the capability equals the registrar value on
        // every host (Windows would otherwise report key-up support).
        ..injectMonitor(NoopKeyboardUpMonitor());
      return makeTestable(
        const SingleChildScrollView(child: KeyboardShortcutSection()),
        locale: const Locale('en'),
        overrides: [
          hotkeyServiceProvider.overrideWith(() => svc),
          settingsProvider.overrideWith(
            () => _FakeSettings(
              AppSettings(
                audioInput: AudioInputSettings(
                  pushToTalk: pushToTalk,
                  holdOrTap: holdOrTap,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Switch toggle(WidgetTester tester) =>
        tester.widget<Switch>(find.byKey(toggleKey));

    testWidgets('with push-to-talk on, the toggle writes holdOrTap only', (
      tester,
    ) async {
      await tester.pumpWidget(subject(supportsKeyUp: true, pushToTalk: true));
      await tester.pumpAndSettle();

      expect(toggle(tester).onChanged, isNotNull);
      await tester.tap(find.byKey(toggleKey));
      await tester.pumpAndSettle();

      final updated = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!;
      expect(updated.audioInput.holdOrTap, isTrue);
      expect(updated.audioInput.pushToTalk, isTrue);
    });

    testWidgets('threshold slider shows only while hold-or-tap is on, '
        'with the value in milliseconds (default 250)', (tester) async {
      await tester.pumpWidget(
        subject(supportsKeyUp: true, pushToTalk: true, holdOrTap: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-hotkey-main-threshold')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.settingsHoldOrTapThresholdValue(250)),
        findsOneWidget,
      );
    });

    testWidgets('threshold slider is hidden while hold-or-tap is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(supportsKeyUp: true, pushToTalk: true, holdOrTap: false),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('settings-hotkey-main-threshold')),
        findsNothing,
      );
    });

    testWidgets('is disabled while push-to-talk itself is off', (tester) async {
      await tester.pumpWidget(subject(supportsKeyUp: true, pushToTalk: false));
      await tester.pumpAndSettle();

      expect(toggle(tester).onChanged, isNull);
    });

    testWidgets('without key-up support (Linux) it is disabled with a visible '
        'reason (UIA-SET-05)', (tester) async {
      await tester.pumpWidget(subject(supportsKeyUp: false, pushToTalk: true));
      await tester.pumpAndSettle();

      expect(toggle(tester).onChanged, isNull);
      // The reason is printed under the row, not only in a hover tooltip.
      // Both dependent rows (push-to-talk and hold-or-tap) explain it.
      expect(
        find.textContaining(
          pushToTalkUnavailableMessage(l10n, operatingSystem: 'other'),
        ),
        findsNWidgets(2),
      );
      expect(
        find.ancestor(
          of: find.byKey(toggleKey),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                w.message ==
                    pushToTalkUnavailableMessage(
                      l10n,
                      operatingSystem: 'other',
                    ),
          ),
        ),
        findsNothing,
      );
    });
  });

  group('KeyboardShortcutSection — Schnellnotiz-Hotkey', () {
    Widget subject({
      AppSettings? settings,
      HotkeyRegistrationStatus status = HotkeyRegistrationStatus.unknown,
      double width = 560,
      Locale locale = const Locale('en'),
    }) => makeTestable(
      MediaQuery(
        data: const MediaQueryData(),
        child: SingleChildScrollView(
          child: SizedBox(
            key: const Key('probeFrame'),
            width: width,
            child: const KeyboardShortcutSection(),
          ),
        ),
      ),
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettings(settings ?? const AppSettings()),
        ),
        quickNoteHotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeQuickNoteStatus(status),
        ),
        // Der dritte Block steht hier als „auf dieser Plattform noch nicht
        // verfügbar" — ein Satz statt Umschalter, Kombination und
        // Ändern-Schaltfläche. Diese Gruppe misst den *Schnellnotiz*-Block:
        // sein Ändern-Button und seine Kombinations-Beschriftung wären sonst
        // nur noch über ihren Index von den gleichnamigen des dritten Blocks
        // zu unterscheiden, und ein Index ist keine Aussage. Das Zusammenspiel
        // beider Blöcke prüft die Snippet-Picker-Gruppe unten.
        snippetPickerAvailabilityProvider.overrideWithValue(false),
      ],
    );

    testWidgets('names where the dictated text lands, without a note picker', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsQuickNoteHotkeyHint), findsOneWidget);
      // Die Ziel-Notiz wird im Notizen-Bereich bestimmt — hier steht die
      // Taste, nicht die Notiz. Ein Auswahlfeld wäre genau die Platzierung,
      // die das Ticket ausschließt.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shortcutBlock-quickNote')),
          matching: find.byType(DropdownButton<String>),
        ),
        findsNothing,
      );
    });

    testWidgets('the toggle writes the quick-note setting, not the main one', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .quickNoteHotkey
            .quickNoteHotkeyEnabled,
        isFalse,
        reason: 'default is off — an update must never claim a hotkey silently',
      );

      await tester.ensureVisible(
        find.byKey(const Key('quickNoteHotkeyToggle')),
      );
      await tester.tap(find.byKey(const Key('quickNoteHotkeyToggle')));
      await tester.pumpAndSettle();

      final updated = container.read(settingsProvider).value!;
      expect(updated.quickNoteHotkey.quickNoteHotkeyEnabled, isTrue);
      expect(
        updated.hotkeyEnabled,
        const AppSettings().hotkeyEnabled,
        reason: 'the main hotkey must be untouched by the subordinate toggle',
      );
    });

    testWidgets('a switched-off quick-note hotkey is out of the tab order', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      // The quick-note block has exactly one „Ändern" button.
      final buttons = find.descendant(
        of: find.byKey(const ValueKey('shortcutBlock-quickNote')),
        matching: find.text(l10n.settingsChangeHotkey),
      );
      expect(buttons, findsOneWidget);

      final node = Focus.of(tester.element(buttons));
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'Tab must not reach the control of a switched-off hotkey',
      );
    });

    testWidgets('shows the stored combination including the display key', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: ';',
              // Layout-abweichende Anzeige-Taste (DE-Tastatur): gespeichert
              // wird ';', angezeigt gehört 'Ö'.
              quickNoteHotkeyKeyDisplay: 'Ö',
              quickNoteHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('an identical combination is refused before it is saved', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: 'Y',
              quickNoteHotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('quickNoteHotkeyChange')),
      );
      await tester.tap(find.byKey(const Key('quickNoteHotkeyChange')));
      await tester.pumpAndSettle();

      // Genau die Kombination des Haupt-Hotkeys aufzeichnen.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .quickNoteHotkey
            .quickNoteHotkeyKey,
        'Y',
        reason: 'the colliding combination must not reach the settings',
      );
      // Der Live-Check im Aufnahme-Dialog benennt den Halter und sperrt Speichern;
      // die Sektion bekommt deshalb keinen zweiten Hinweis.
      expect(
        find.byKey(const ValueKey('hotkey-recorder-holder')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.settingsDictationHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('quickNoteHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('a free combination is saved and shows no collision notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('quickNoteHotkeyChange')),
      );
      await tester.tap(find.byKey(const Key('quickNoteHotkeyChange')));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final saved = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!.quickNoteHotkey;
      expect(saved.quickNoteHotkeyKey, 'K');
      expect(
        find.byKey(const Key('quickNoteHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('the recorder still warns about system-reserved combinations', (
      tester,
    ) async {
      // Die System-Konflikt-Warnung steckt im Aufzeichnungs-Dialog, der hier
      // wiederverwendet wird — dieser Test hält fest, dass sie den zweiten
      // Aufrufer auch wirklich erreicht.
      //
      // Der Eintrag kommt aus der Liste der laufenden Plattform, statt eine
      // Kombination fest zu verdrahten, die auf macOS/Windows/Linux
      // unterschiedlich reserviert ist. `isNotEmpty` ist dabei die Zusicherung,
      // dass der Test nicht mangels Liste heimlich nichts prüft.
      final reserved = platformConflicts;
      expect(
        reserved.any((e) => e.modifiers == 'meta' && e.key == 'L'),
        isTrue,
        reason: 'every desktop platform ships a system-conflict list',
      );
      final entry = reserved.first;

      await tester.pumpWidget(
        subject(
          settings: AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: entry.key,
              quickNoteHotkeyModifiers: entry.modifiers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('quickNoteHotkeyChange')),
      );
      await tester.tap(find.byKey(const Key('quickNoteHotkeyChange')));
      await tester.pumpAndSettle();

      // The warning comes with a recorded combination (38695f76f): the user
      // presses Meta+L, which the platform reserves.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a failed registration says "not active" and asks for a new '
        'combination', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
            ),
          ),
          status: HotkeyRegistrationStatus.conflict,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quickNoteHotkeyInactiveNotice')),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsQuickNoteHotkeyInactive), findsOneWidget);
    });

    testWidgets('a switched-off hotkey never claims to have failed', (
      tester,
    ) async {
      // Der Registrierungs-Status ist ein In-Memory-Wert, den nur
      // Registrierungs-Versuche schreiben — Abschalten setzt ihn nicht zurück.
      // Ohne die Enabled-Bedingung stünde „nicht aktiv, bitte neu belegen" an
      // einem Hotkey, den der Nutzer gerade selbst ausgeschaltet hat.
      await tester.pumpWidget(
        subject(status: HotkeyRegistrationStatus.conflict),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('quickNoteHotkeyInactiveNotice')),
        findsNothing,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Snippet-Picker-Hotkey — der dritte, nachgeordnete Eintrag (Ticket 27)
  // ---------------------------------------------------------------------------

  group('KeyboardShortcutSection — Snippet-Picker-Hotkey', () {
    Widget subject({
      AppSettings? settings,
      HotkeyRegistrationStatus status = HotkeyRegistrationStatus.unknown,
      bool available = true,
      double width = 560,
      Locale locale = const Locale('en'),
    }) => makeTestable(
      MediaQuery(
        data: const MediaQueryData(),
        child: SingleChildScrollView(
          child: SizedBox(
            key: const Key('probeFrame'),
            width: width,
            child: const KeyboardShortcutSection(),
          ),
        ),
      ),
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettings(settings ?? const AppSettings()),
        ),
        snippetPickerHotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeSnippetPickerStatus(status),
        ),
        // Die eine Verfügbarkeits-Aussage (Ticket 26), hier gestellt: auf
        // einem macOS-Rechner gäbe es den „nicht verfügbar"-Zweig sonst
        // nirgends zu sehen, und auf einem Windows-Rechner den anderen nicht.
        snippetPickerAvailabilityProvider.overrideWithValue(available),
      ],
    );

    testWidgets('renders as its own entry below the quick-note block', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.settingsSnippetPickerHotkeyEnabled),
        findsOneWidget,
      );
      final quickNoteY = tester
          .getTopLeft(find.text(l10n.settingsQuickNoteHotkeyEnabled))
          .dy;
      final snippetY = tester
          .getTopLeft(find.text(l10n.settingsSnippetPickerHotkeyEnabled))
          .dy;
      expect(snippetY, greaterThan(quickNoteY));
    });

    testWidgets('says what the hotkey opens, and gives the spoken trigger word '
        'its own row under it', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsSnippetPickerHotkeyHint), findsOneWidget);
      // Das gesprochene Trigger-Wort ist ein eigener Eintrag (UX-030) und kein
      // Umschalter dieses Blocks: die beiden Auslösewege öffnen dasselbe
      // Panel, bleiben aber getrennte Einstellungen.
      expect(find.text(l10n.snippetsPickerTriggerLabel), findsOneWidget);
      expect(
        find.byKey(settingsRowKey('general-snippet-picker-trigger')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('snippetPickerHotkeyToggle')),
        findsOneWidget,
      );
    });

    testWidgets('the toggle writes the snippet-picker setting, not the other '
        'two', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyEnabled,
        isFalse,
        reason: 'default is off — an update must never claim a hotkey silently',
      );

      // Scrolled into view first: since the hold-or-tap row (ticket
      // catchup/07) the toggle sits below the 800x600 test surface.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyToggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyToggle')));
      await tester.pumpAndSettle();

      final updated = container.read(settingsProvider).value!;
      expect(updated.snippetPickerHotkey.snippetPickerHotkeyEnabled, isTrue);
      expect(updated.hotkeyEnabled, const AppSettings().hotkeyEnabled);
      expect(
        updated.quickNoteHotkey.quickNoteHotkeyEnabled,
        const AppSettings().quickNoteHotkey.quickNoteHotkeyEnabled,
        reason: 'the two sibling hotkeys must be untouched by this toggle',
      );
    });

    testWidgets(
      'a switched-off snippet-picker hotkey is out of the tab order',
      (tester) async {
        await tester.pumpWidget(subject());
        await tester.pumpAndSettle();

        final node = Focus.of(
          tester.element(find.byKey(const Key('snippetPickerHotkeyChange'))),
        );
        node.requestFocus();
        await tester.pump();
        expect(
          node.hasFocus,
          isFalse,
          reason: 'Tab must not reach the control of a switched-off hotkey',
        );
      },
    );

    testWidgets('shows the stored combination including the display key', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: ';',
              snippetPickerHotkeyKeyDisplay: 'Ö',
              snippetPickerHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('a combination already used by the main hotkey is refused '
        'before it is saved', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: 'E',
              snippetPickerHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyKey,
        'E',
        reason: 'the colliding combination must not reach the settings',
      );
      expect(
        find.byKey(const ValueKey('hotkey-recorder-holder')),
        findsOneWidget,
      );
      expect(
        find.text(
          l10n.settingsDictationHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('snippetPickerHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('a combination already used by the quick-note hotkey is '
        'refused too — all three are checked against each other', (
      tester,
    ) async {
      // Der Fall, den es vor dem dritten Hotkey nicht geben konnte: zwei
      // *nachgeordnete* Hotkeys, die einander im Weg stehen. Ginge die Prüfung
      // nur gegen den Haupt-Hotkey, fiele genau das durch.
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: 'Y',
              quickNoteHotkeyModifiers: 'ctrl+alt',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: 'E',
              snippetPickerHotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      );
      expect(
        container
            .read(settingsProvider)
            .value!
            .snippetPickerHotkey
            .snippetPickerHotkeyKey,
        'E',
      );
      expect(
        find.text(
          l10n.settingsSnippetPickerHotkeyCollision(
            l10n.settingsHotkeyActionQuickNote,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a free combination is saved and shows no collision notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      final saved = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!.snippetPickerHotkey;
      expect(saved.snippetPickerHotkeyKey, 'K');
      expect(
        find.byKey(const Key('snippetPickerHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('the recorder still warns about system-reserved combinations', (
      tester,
    ) async {
      final reserved = platformConflicts;
      expect(reserved, isNotEmpty);
      final entry = reserved.first;

      await tester.pumpWidget(
        subject(
          settings: AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
              snippetPickerHotkeyKey: entry.key,
              snippetPickerHotkeyModifiers: entry.modifiers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Der dritte Block steht am unteren Ende einer Sektion, die höher ist
      // als das Testfenster — in der App scrollt die Einstellungsseite,
      // hier muss der Test das selbst tun.
      await tester.ensureVisible(
        find.byKey(const Key('snippetPickerHotkeyChange')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snippetPickerHotkeyChange')));
      await tester.pumpAndSettle();

      // The warning comes with a recorded combination (38695f76f): the user
      // presses Meta+L, which the platform reserves.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hotkeyConflictWarning')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a failed registration says "not active" and asks for a new '
        'combination', (tester) async {
      await tester.pumpWidget(
        subject(
          settings: const AppSettings(
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
          status: HotkeyRegistrationStatus.conflict,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyInactiveNotice')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.settingsSnippetPickerHotkeyInactive),
        findsOneWidget,
      );
    });

    testWidgets('a switched-off hotkey never claims to have failed', (
      tester,
    ) async {
      await tester.pumpWidget(
        subject(status: HotkeyRegistrationStatus.conflict),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyInactiveNotice')),
        findsNothing,
      );
    });

    testWidgets('where the platform has no picker, the row states that instead '
        'of offering a hotkey that could not open anything', (tester) async {
      await tester.pumpWidget(
        subject(
          available: false,
          settings: const AppSettings(
            // Selbst ein (etwa importierter) eingeschalteter Hotkey macht die
            // Zeile hier nicht bedienbar — die Plattform-Aussage schlägt den
            // gespeicherten Zustand.
            snippetPickerHotkey: SnippetPickerHotkeySettings(
              snippetPickerHotkeyEnabled: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('snippetPickerHotkeyUnavailable')),
        findsOneWidget,
      );
      expect(find.text(l10n.snippetsPickerUnavailable), findsOneWidget);
      // Weder Umschalter noch Ändern-Schaltfläche: nichts, was den Eindruck
      // erweckt, hier ließe sich etwas einschalten.
      expect(find.byKey(const Key('snippetPickerHotkeyToggle')), findsNothing);
      expect(find.byKey(const Key('snippetPickerHotkeyChange')), findsNothing);
      expect(
        find.byKey(const Key('snippetPickerHotkeyComboLine')),
        findsNothing,
        reason: 'no combination is shown for a hotkey that cannot be used',
      );
    });
  });

  group('AudioSection', () {
    testWidgets('does NOT render Hold to Record toggle in audio block', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const AudioSection(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHoldToRecord), findsNothing);
    });
  });
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeFallback extends GlobalHotkeyFallbackController {
  _FakeFallback(this._active);

  final bool _active;

  @override
  bool build() => _active;
}

class _FakeSnippetPickerStatus
    extends SnippetPickerHotkeyRegistrationStatusController {
  _FakeSnippetPickerStatus(this._status);

  final HotkeyRegistrationStatus _status;

  @override
  HotkeyRegistrationStatus build() => _status;
}

class _FakeQuickNoteStatus extends QuickNoteHotkeyRegistrationStatusController {
  _FakeQuickNoteStatus(this._status);

  final HotkeyRegistrationStatus _status;

  @override
  HotkeyRegistrationStatus build() => _status;
}

class _KeyUpRegistrar implements HotKeyRegistrar {
  _KeyUpRegistrar({required this.supportsKeyUp});

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}
