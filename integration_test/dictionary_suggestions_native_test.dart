/// #321 evidence in the native desktop app: the suggestions tab of the
/// dictionary in each state (loading, empty, load error, list, rejected with
/// undo), at 100 % and 200 % text size and in a narrow window, so the reflow
/// of the decision buttons can be seen. A layout overflow fails the run.
/// `SHOT_DIR` writes the rendered tab as PNG (for guests without a desktop,
/// e.g. under Xvfb).
/// Run: `flutter test integration_test/dictionary_suggestions_native_test.dart -d linux`
library;

import 'dart:async';
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
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/dictionary/dictionary_notice.dart';
import 'package:whispaste/features/dictionary/dictionary_suggestions_tab.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_candidate_detector.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../test/fixtures/test_helpers.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');
const _shotKey = ValueKey('suggestions-native-shot');

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotDir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_shotDir/$name.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint('NATIVE shot ${file.path}');
  });
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? AppSettings.defaults));
  }
}

const _pairs = [
  ('Wispaste', 'WhisPaste'),
  ('Sylvio', 'Silvio'),
  ('Kubernetis', 'Kubernetes'),
];

Future<HistoryDatabase> _seeded(WidgetTester tester) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final now = DateTime.now();
  await tester.runAsync(() async {
    for (final (i, (from, to)) in _pairs.indexed) {
      await db.upsertCorrectionObservation(
        id: 'c$i',
        normalizedKey: normalizeCorrectionKey(from, to),
        sourceText: from,
        targetText: to,
        occurrenceCount: correctionCandidateThreshold + i,
        status: CorrectionObservationStatus.pending.name,
        source: CorrectionSignalSource.manualEdit.name,
        unit: correctionUnitWord,
        firstSeenAt: now,
        lastSeenAt: now,
      );
    }
  });
  return db;
}

/// The tab as the dictionary page shows it (notice slot above), in a frame of
/// [width] and at [scale] text size.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  HistoryDatabase? db,
  List overrides = const [],
}) async {
  // The native window is only 720 px high; a taller logical view lets the
  // 200 % frames show the rows instead of cutting them off.
  final height = scale == 1 ? 760.0 : (width < 600 ? 2700.0 : 1500.0);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(1280, height);
  addTearDown(tester.view.reset);
  WpColors.activate(wpNavyColors);
  addTearDown(() => WpColors.activate(wpDarkColors));
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _shotKey,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: const Column(
                    children: [
                      WpPageNoticeSlot(page: dictionaryNoticePage),
                      Expanded(child: DictionarySuggestionsTab()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      size: Size(1280, height),
      locale: const Locale('de'),
      theme: wpThemeFor(wpNavyColors),
      db: db,
      overrides: [settingsProvider.overrideWith(_Settings.new), ...overrides],
    ),
  );
}

/// The loading bars shimmer forever; a few frames are enough to render them.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, width, scale) in [
    ('wide-100', 900.0, 1.0),
    ('wide-200', 900.0, 2.0),
    ('narrow-200', 420.0, 2.0),
  ]) {
    testWidgets('loading, $name', (tester) async {
      final pending = Completer<List<CorrectionCandidate>>();
      await _pump(
        tester,
        width: width,
        scale: scale,
        overrides: [
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) => pending.future,
          ),
        ],
      );
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('dictionary-suggestions-loading')),
        findsOneWidget,
      );
      await _shot(tester, 'suggestions-loading-$name');
      pending.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('empty, $name', (tester) async {
      await _pump(tester, width: width, scale: scale);
      await tester.pumpAndSettle();
      await _shot(tester, 'suggestions-empty-$name');
    });

    testWidgets('load error, $name', (tester) async {
      await _pump(
        tester,
        width: width,
        scale: scale,
        overrides: [
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) => Future.error(StateError('database is locked')),
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-suggestions-retry')),
        findsOneWidget,
      );
      await _shot(tester, 'suggestions-error-$name');
    });

    testWidgets('list, $name', (tester) async {
      await _pump(
        tester,
        width: width,
        scale: scale,
        db: await _seeded(tester),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictionary-suggestion-reject-c0')),
        findsOneWidget,
      );
      await _shot(tester, 'suggestions-list-$name');
    });
  }

  testWidgets('rejected with undo, wide-100', (tester) async {
    await _pump(tester, width: 900, scale: 1, db: await _seeded(tester));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('dictionary-suggestion-reject-c0')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dictionary-suggestion-undo')),
      findsOneWidget,
    );
    await _shot(tester, 'suggestions-rejected-undo-wide-100');
    // Let the undo window close so no timer is left.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });
}
