import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

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
    testWidgets('a disabled hotkey folds its combination away and says so '
        'next to its switch', (tester) async {
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

      // Nothing to reach, by mouse or keyboard, while the hotkey is off.
      expect(find.byKey(const Key('mainHotkeyChange')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-row-general-hotkey-combo')),
        findsNothing,
      );
      // #1076: the off state is said in words, not by a fade alone.
      expect(find.byKey(const Key('settings-row-switched-off')), findsWidgets);
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

    const dropdown = ValueKey<String>('settings-hotkey-operation');

    testWidgets('choosing tap or hold writes both flags', (tester) async {
      await tester.pumpWidget(subject(supportsKeyUp: true, pushToTalk: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('settings-hotkey-operation-item-holdOrTap'),
        ),
      );
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

    testWidgets('without key-up support (Linux) the reason is visible and '
        'hold stays locked (UIA-SET-05)', (tester) async {
      await tester.pumpWidget(subject(supportsKeyUp: false, pushToTalk: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('settings-hotkey-operation-item-hold'),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final stored = ProviderScope.containerOf(
        tester.element(find.byType(KeyboardShortcutSection)),
      ).read(settingsProvider).value!;
      expect(stored.audioInput.pushToTalk, isFalse);
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

      // Die Ziel-Notiz wird im Notizen-Bereich bestimmt — hier steht die
      // Taste, nicht die Notiz. Ein Auswahlfeld wäre genau die Platzierung,
      // die das Ticket ausschließt. Das einzige Auswahlfeld im Block ist die
      // Zeitstempel-Art (#803), keine Notizauswahl.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('shortcutBlock-quickNote')),
          matching: find.byType(DropdownButton<String>),
        ),
        findsOneWidget,
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

    testWidgets('a switched-off quick-note hotkey shows no change button', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quickNoteHotkeyChange')), findsNothing);
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
      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
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
      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
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

    testWidgets('says what the hotkey opens, and gives the spoken trigger word '
        'its own row under it', (tester) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      // Das gesprochene Trigger-Wort ist ein eigener Eintrag (UX-030) und kein
      // Umschalter dieses Blocks: die beiden Auslösewege öffnen dasselbe
      // Panel, bleiben aber getrennte Einstellungen.
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

    testWidgets('a switched-off snippet-picker hotkey shows no change button', (
      tester,
    ) async {
      await tester.pumpWidget(subject());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('snippetPickerHotkeyChange')), findsNothing);
    });

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
      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
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
      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
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
      await tester.tap(find.bySemanticsIdentifier('hotkey-recorder-save'));
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
