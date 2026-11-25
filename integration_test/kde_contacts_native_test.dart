/// #2041 evidence in the native Linux app: the contact page against a real
/// KDE address book (Akonadi on the session bus, its personal contacts
/// resource). First read with consent, the comparison when the page opens
/// again after the address book changed, and the withdrawal. `SHOT_DIR`
/// writes the page as PNG at each step (for guests without a desktop, e.g.
/// under Xvfb).
///
/// Needs Akonadi with a contacts resource holding the contacts "Lea Wolf"
/// (company "Nordwind GmbH", with e-mail and phone) and "Ida Berg";
/// `KDE_CHANGE` names a command that then removes Ida Berg and adds
/// "Tom Rau". Without Akonadi on the bus or without such a resource the
/// test fails.
/// Run: `flutter test integration_test/kde_contacts_native_test.dart
/// -d linux --dart-define=KDE_CHANGE=CMD --dart-define=SHOT_DIR=DIR` inside
/// the KDE session (or `dbus-run-session` with Akonadi installed).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/contact_import_page.dart';
import 'package:whispaste/services/dictionary/contact_names.dart';
import 'package:whispaste/services/dictionary/kde_contact_source.dart';

import '../test/fixtures/test_helpers.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');
const _changeCommand = String.fromEnvironment('KDE_CHANGE');
const _shotKey = ValueKey('kde-contacts-native-shot');

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotDir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  final image = await boundary.toImage(pixelRatio: 1.5);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$_shotDir/$name.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  debugPrint('NATIVE shot ${file.path}');
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

/// Pumps real frames until [finder] shows; the bus answers in real time.
Future<void> _until(WidgetTester tester, Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      await _shot(tester, 'failed');
      for (final e in find.byType(Text).evaluate()) {
        debugPrint('NATIVE text ${(e.widget as Text).data}');
      }
      fail('not shown in 60 s: $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// [round] gives the page a fresh state (as opening it again does) while the
/// provider scope, and with it the database, stays.
Future<void> _pumpPage(
  WidgetTester tester,
  HistoryDatabase db, {
  int round = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 760);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    makeTestable(
      RepaintBoundary(
        key: _shotKey,
        child: ContactImportPage(key: ValueKey(round)),
      ),
      size: const Size(1000, 760),
      locale: const Locale('de'),
      db: db,
      overrides: [settingsProvider.overrideWith(_Settings.new)],
    ),
  );
}

Future<void> _tap(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey<String>(id));
  await _until(tester, button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('KDE address book: read with consent, compare on open, '
      'withdraw', (tester) async {
    final availability = await KdeContactSource().availability();
    // Run deliberately by path only: a guest without Akonadi is a wrong setup,
    // not a pass.
    expect(
      availability,
      SystemContactsAvailability.available,
      reason: 'needs Akonadi on the session bus with a contacts resource',
    );
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeAppSettings({'replacementsSamplesSeeded': '1'});

    // 1. The page offers the KDE address book.
    await _pumpPage(tester, db);
    await _until(tester, find.byKey(const ValueKey('dictionary-contacts-kde')));
    await _shot(tester, '1-page');

    // 2. Reading shows names and the company, never e-mail or phone.
    await _tap(tester, 'dictionary-contacts-kde');
    await _until(tester, find.textContaining('Lea Wolf'));
    expect(find.textContaining('Ida Berg'), findsOneWidget);
    expect(find.textContaining('Nordwind GmbH'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('123456'), findsNothing);
    await _shot(tester, '2-preview');

    // 3. Consent creates the group.
    await _tap(tester, 'dictionary-contacts-confirm');
    await _until(tester, find.textContaining('KDE-Adressbuch: 3 Namen'));
    final group = (await db.readContactNameGroups()).single;
    expect(group.sourceKind, kKdeContactsKind);
    await _shot(tester, '3-imported');

    // 4. The address book changes; opening the page again shows the
    // changes for confirmation.
    if (_changeCommand.isNotEmpty) {
      final change = await Process.run('sh', ['-c', _changeCommand]);
      debugPrint('NATIVE change ${change.stdout}${change.stderr}');
      expect(change.exitCode, 0, reason: '${change.stdout}${change.stderr}');
      await _pumpPage(tester, db, round: 1);
      await _until(tester, find.textContaining('Tom Rau'));
      expect(find.textContaining('hat sich geändert'), findsOneWidget);
      expect(
        find.textContaining('Ida Berg — Nicht mehr im KDE-Adressbuch'),
        findsOneWidget,
      );
      await _shot(tester, '4-changed-on-open');
      await _tap(tester, 'dictionary-contacts-confirm');
      await _until(tester, find.textContaining('1 entfernt'));
      final names = {
        for (final r in await db.readAllReplacements()) r.row.replacement,
      };
      expect(names, {'Lea Wolf', 'Nordwind GmbH', 'Tom Rau'});
      await _shot(tester, '5-updated');
    }

    // 5. Removing withdraws the consent and deletes the names.
    await _tap(tester, 'dictionary-contacts-group-remove-0');
    await _tap(tester, 'confirm-dialog-confirm');
    await _until(tester, find.textContaining('Namen entfernt'));
    expect(await db.readContactNameGroups(), isEmpty);
    expect(await db.readAllReplacements(), isEmpty);
    await _shot(tester, '6-removed');
  });
}
