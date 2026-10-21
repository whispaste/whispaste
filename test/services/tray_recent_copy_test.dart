import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/clipboard_history/app_clipboard.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/tray_recent_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tray recent items map to their recording', () {
    test('a recent-<id> key round-trips to the recording id', () {
      expect(trayRecentIdFromKey(trayRecentKey('abc-123')), 'abc-123');
      expect(trayRecentIdFromKey(TrayCommandIds.unlockHistory), isNull);
    });

    test('copying a key copies the text of that recording only', () async {
      final written = <String>[];
      final copier = TrayRecentCopier(
        isHidden: () => false,
        write: (text) async => written.add(text),
      )..replace({'a': 'first text', 'b': 'second text'});

      final id = trayRecentIdFromKey(trayRecentKey('b'))!;
      await copier.copy(id);
      expect(written, ['second text']);
    });
  });

  group('TrayRecentCopier', () {
    test('an id that is not listed writes nothing', () async {
      final written = <String>[];
      final copier = TrayRecentCopier(
        isHidden: () => false,
        write: (text) async => written.add(text),
      )..replace({'a': 'text'});
      await copier.copy('missing');
      expect(written, isEmpty);
    });

    test('a lock engaging after the last build blocks the copy', () async {
      var hidden = false;
      final written = <String>[];
      final copier = TrayRecentCopier(
        isHidden: () => hidden,
        write: (text) async => written.add(text),
      )..replace({'a': 'secret'});

      hidden = true;
      await copier.copy('a');
      expect(written, isEmpty);
      // The texts are gone for good, not just skipped once.
      hidden = false;
      await copier.copy('a');
      expect(written, isEmpty);
    });

    test('nothing is kept while the history is hidden', () async {
      final written = <String>[];
      final copier = TrayRecentCopier(
        isHidden: () => true,
        write: (text) async => written.add(text),
      )..replace({'a': 'secret'});
      await copier.copy('a');
      expect(written, isEmpty);
    });

    test('clear drops every text', () async {
      final written = <String>[];
      final copier = TrayRecentCopier(
        isHidden: () => false,
        write: (text) async => written.add(text),
      )..replace({'a': 'text'});
      copier.clear();
      await copier.copy('a');
      expect(written, isEmpty);
    });
  });

  group('writeTrayCopyTransient', () {
    late List<MethodCall> clipboardCalls;

    setUp(() {
      clipboardCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            clipboardCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('uses the history-excluded write and skips the plain write', () async {
      await writeTrayCopyTransient('copied', excludedWrite: (_) async => true);
      expect(clipboardCalls, isEmpty);
    });

    test(
      'falls back to the plain write when exclusion is unavailable',
      () async {
        await writeTrayCopyTransient(
          'copied',
          excludedWrite: (_) async => false,
        );
        expect(clipboardCalls.map((c) => c.method), ['Clipboard.setData']);
      },
    );

    test(
      'logs the plain-write fallback once and never the text (GS-114)',
      () async {
        resetTrayCopyFallbackLogForTesting();
        final records = <LogRecord>[];
        Logger.root.level = Level.ALL;
        final sub = Logger.root.onRecord
            .where((r) => r.loggerName == 'TrayRecentCopy')
            .listen(records.add);
        addTearDown(sub.cancel);

        await writeTrayCopyTransient(
          'secret tray text',
          excludedWrite: (_) async => false,
        );
        await writeTrayCopyTransient(
          'secret tray text',
          excludedWrite: (_) async => false,
        );

        expect(records, hasLength(1));
        expect(records.single.level, Level.INFO);
        expect(records.single.message, isNot(contains('secret tray text')));
      },
    );

    test('logs nothing when the excluded write succeeds', () async {
      resetTrayCopyFallbackLogForTesting();
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'TrayRecentCopy')
          .listen(records.add);
      addTearDown(sub.cancel);

      await writeTrayCopyTransient('copied', excludedWrite: (_) async => true);

      expect(records, isEmpty);
    });

    test('marks the text as a transient self-write', () async {
      const text = 'transient tray text';
      await writeTrayCopyTransient(text, excludedWrite: (_) async => true);
      expect(
        AppClipboard.transientWrites.shouldSuppress(
          ClipboardFingerprint.ofText(text),
        ),
        isTrue,
      );
    });
  });

  group('recent item labels in six languages', () {
    test('show the time and the word count', () {
      for (final locale in L10n.supportedLocales) {
        final l10n = lookupL10n(locale);
        final label = l10n.trayRecentMeta('14:32', 23);
        expect(label, startsWith('14:32'), reason: locale.languageCode);
        expect(label, contains('23'), reason: locale.languageCode);
        expect(
          label,
          isNot(contains('{')),
          reason: '${locale.languageCode} placeholder not filled',
        );
      }
    });

    test('german names the words', () {
      expect(
        lookupL10n(const Locale('de')).trayRecentMeta('14:32', 23),
        '14:32 · 23 Wörter',
      );
    });
  });

  group(
    'tray text preview (decision 2026-10-21: always on, off with a PIN)',
    () {
      test('is on without a history PIN', () {
        expect(trayTextPreviewEnabled(historyPin: ''), isTrue);
      });

      test('is off as soon as a history PIN is set', () {
        expect(trayTextPreviewEnabled(historyPin: '1234'), isFalse);
      });

      test('shows the first non-blank line, cut with an ellipsis', () {
        expect(trayRecentLabel('  Hello\nworld '), 'Hello');
        final label = trayRecentLabel('a' * 100);
        expect(label.length, trayRecentLabelMaxLength);
        expect(label.endsWith('\u2026'), isTrue);
        expect(trayRecentLabel('   \n  '), '\u2026');
      });
    },
  );
}
