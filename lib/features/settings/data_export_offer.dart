/// Regular offer to export the recordings and the dictionary (#1023, part
/// of #591).
///
/// The history is encrypted with the data key; when that key is lost (new
/// computer, new user account, deleted keychain) the app starts empty and
/// the old file can only be read with the key again. An export as plain
/// files is the cheap insurance against that: every
/// [kDataExportOfferInterval] the app asks once, calmly, whether to export.
///
/// Rules (see `decideDataExportOffer`):
/// - only after the onboarding, never over it, and only when there are
///   recordings to lose,
/// - the clock starts the first time the rule could apply, so a new user is
///   not asked on day one,
/// - the interval counts from the later of the last offer and the last
///   export; "Later" counts as an offer,
/// - the dialog waits for the nudge gate (no dictation, app idle).
///
/// "Export" asks for a folder and writes two files there: the recordings as
/// JSON (the format of the history export, archived ones included, the trash
/// left out) and the dictionary as CSV (the format of the dictionary export,
/// importable again). Timestamps live in the `app_settings` table, outside
/// the settings export.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../services/dictionary/replacement_csv.dart';
import '../../services/history/history_exporter.dart';
import '../../services/nudge_gate.dart';
import '../../services/replacements/text_replacement_matcher.dart'
    show TextReplacementMatchMode;
import '../../widgets/dialog.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_page_notice.dart';
import '../history/data/export_service.dart';

final _log = AppLogger('DataExportOffer');

/// Time between two offers.
const kDataExportOfferInterval = Duration(days: 30);

/// `app_settings` key: when the offer was last shown (or its clock started).
const dataExportOfferedAtKey = 'data_export_offered_at';

/// `app_settings` key: when the last export through the offer succeeded.
const dataExportDoneAtKey = 'data_export_done_at';

/// What the offer does at one check.
enum DataExportOfferStep {
  /// Nothing now.
  wait,

  /// First check that could apply: remember now, ask after the interval.
  startClock,

  /// Show the offer.
  offer,
}

/// Pure decision of the offer; see the library comment.
DataExportOfferStep decideDataExportOffer({
  required DateTime now,
  required bool hasData,
  DateTime? offeredAt,
  DateTime? exportedAt,
}) {
  if (!hasData) return DataExportOfferStep.wait;
  final last = switch ((offeredAt, exportedAt)) {
    (null, null) => null,
    (final a?, null) => a,
    (null, final b?) => b,
    (final a?, final b?) => a.isAfter(b) ? a : b,
  };
  if (last == null) return DataExportOfferStep.startClock;
  return now.difference(last) >= kDataExportOfferInterval
      ? DataExportOfferStep.offer
      : DataExportOfferStep.wait;
}

/// What [exportRecordingsAndDictionary] wrote.
class DataExportResult {
  const DataExportResult({
    required this.recordings,
    required this.dictionaryEntries,
  });

  final int recordings;
  final int dictionaryEntries;
}

/// File names of an export on [now] (date only, so one export per day
/// replaces the files of the same day instead of piling up).
({String recordings, String dictionary}) dataExportFileNames(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${now.year}-${two(now.month)}-${two(now.day)}';
  return (
    recordings: 'whispaste-recordings-$day.json',
    dictionary: 'whispaste-dictionary-$day.csv',
  );
}

/// Writes the recordings (JSON) and the dictionary (CSV) of [db] into
/// [folder]. Archived recordings are included, the trash is not. A part
/// without content writes no file. Throws when a file could not be written.
Future<DataExportResult> exportRecordingsAndDictionary(
  HistoryDatabase db,
  String folder, {
  required DateTime now,
  Future<int> Function(List<ExportEntry>, ExportFormat, String) exporter =
      ExportService.export,
}) async {
  final names = dataExportFileNames(now);
  final entries =
      await (db.select(db.historyEntries)
            ..where((e) => e.deletedAt.isNull())
            ..orderBy([(e) => OrderingTerm.asc(e.timestamp)]))
          .get();
  final rows = entries.map(HistoryExporter.toExportEntry).toList();
  if (rows.isNotEmpty) {
    await exporter(rows, ExportFormat.json, p.join(folder, names.recordings));
  }
  final replacements = await db.readAllReplacements();
  if (replacements.isNotEmpty) {
    final csv = encodeReplacementsCsv([
      for (final r in replacements)
        ReplacementCsvRow(
          triggers: r.triggers,
          replacement: r.row.replacement,
          matchMode: r.row.matchMode == 'fuzzy'
              ? TextReplacementMatchMode.fuzzy
              : TextReplacementMatchMode.exact,
          fuzzyThreshold: r.row.fuzzyThreshold,
        ),
    ], meta: ReplacementCsvMeta(name: 'WhisPaste', created: now));
    await File(p.join(folder, names.dictionary)).writeAsString(csv);
  }
  return DataExportResult(
    recordings: rows.length,
    dictionaryEntries: replacements.length,
  );
}

/// Asks for the target folder; null when the user cancels. Replaced in
/// tests.
final dataExportFolderPickerProvider = Provider<Future<String?> Function()>(
  (ref) => getDirectoryPath,
);

/// Clock of the offer; replaced in tests.
final dataExportClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// How often a running app checks again; the app often stays open for days.
const kDataExportOfferRecheck = Duration(hours: 6);

/// Checks the offer after the start and every [kDataExportOfferRecheck];
/// renders no UI of its own.
class DataExportOfferWatcher extends ConsumerStatefulWidget {
  const DataExportOfferWatcher({super.key});

  @override
  ConsumerState<DataExportOfferWatcher> createState() =>
      _DataExportOfferWatcherState();
}

class _DataExportOfferWatcherState
    extends ConsumerState<DataExportOfferWatcher> {
  bool _started = false;
  bool _running = false;
  Timer? _recheck;

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  bool _ready() {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return false;
    return settings.onboarding.onboardingCompleted &&
        !ref.read(onboardingSurfaceActiveProvider);
  }

  Future<DataExportOfferStep> _decide(HistoryDatabase db) async {
    final now = ref.read(dataExportClockProvider)();
    final hasData = await db.countActive() > 0;
    final offeredAt = DateTime.tryParse(
      await db.readAppSetting(dataExportOfferedAtKey) ?? '',
    );
    final exportedAt = DateTime.tryParse(
      await db.readAppSetting(dataExportDoneAtKey) ?? '',
    );
    return decideDataExportOffer(
      now: now,
      hasData: hasData,
      offeredAt: offeredAt,
      exportedAt: exportedAt,
    );
  }

  Future<void> _stamp(HistoryDatabase db, String key) => db.writeAppSetting(
    key,
    ref.read(dataExportClockProvider)().toUtc().toIso8601String(),
  );

  Future<void> _run() async {
    if (_running || !mounted || !_ready()) return;
    _running = true;
    try {
      final db = ref.read(historyDatabaseProvider);
      switch (await _decide(db)) {
        case DataExportOfferStep.wait:
          return;
        case DataExportOfferStep.startClock:
          await _stamp(db, dataExportOfferedAtKey);
          return;
        case DataExportOfferStep.offer:
          break;
      }
      await ref.read(nudgeGateProvider).whenAllowed();
      if (!mounted || !_ready()) return;
      final export = await _ask();
      if (!mounted) return;
      await _stamp(db, dataExportOfferedAtKey);
      if (export == true) await _export(db);
    } on Object catch (e) {
      _log.warning('Data export offer failed: ${e.runtimeType}');
    } finally {
      _running = false;
    }
  }

  Future<bool?> _ask() {
    final l10n = L10n.of(context);
    return showWpDialog<bool>(
      context: context,
      title: l10n.dataExportOfferTitle,
      content: Semantics(
        identifier: 'data-export-offer-body',
        child: Text(l10n.dataExportOfferBody),
      ),
      actions: [
        WpDialogAction<bool>(
          label: l10n.dataKeyLater,
          testId: 'data-export-offer-later',
          role: WpDialogActionRole.cancel,
          value: false,
        ),
        WpDialogAction<bool>(
          label: l10n.dataExportOfferExport,
          testId: 'data-export-offer-export',
          role: WpDialogActionRole.primary,
          value: true,
        ),
      ],
    );
  }

  Future<void> _export(HistoryDatabase db) async {
    final folder = await ref.read(dataExportFolderPickerProvider)();
    if (folder == null || !mounted) return;
    final l10n = L10n.of(context);
    try {
      await exportRecordingsAndDictionary(
        db,
        folder,
        now: ref.read(dataExportClockProvider)(),
      );
      await _stamp(db, dataExportDoneAtKey);
      if (!mounted) return;
      showWpConfirmation(
        context,
        id: 'data-export-offer-done',
        message: l10n.dataExportOfferDone(folder),
      );
    } on Object catch (e) {
      // The error type only: a path can name the user.
      _log.warning('Data export failed: ${e.runtimeType}');
      if (!mounted) return;
      showWpAppError(
        context,
        id: 'data-export-offer-failed',
        message: l10n.dataExportOfferFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    ref.watch(onboardingSurfaceActiveProvider);
    if (!_started && _ready()) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_run());
        _recheck = Timer.periodic(
          kDataExportOfferRecheck,
          (_) => unawaited(_run()),
        );
      });
    }
    return const SizedBox.shrink();
  }
}
