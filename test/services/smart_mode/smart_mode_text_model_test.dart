import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_text_model.dart';

void main() {
  // Before the initial disk scan the file's presence is unknown, and unknown
  // must not lock the presets or tell the user to download.
  group('smartModeTextModelStatusProvider', () {
    Future<SmartModeTextModelStatus> read(SmartModeDownloadState state) async {
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          smartModeLocalEngineAvailableProvider.overrideWith((ref) => true),
          smartModeDownloadProvider.overrideWith(() => _Download(state)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(settingsProvider.future);
      return c.read(smartModeTextModelStatusProvider);
    }

    test('nothing is missing before the initial disk scan', () async {
      expect(
        await read(const SmartModeDownloadState(scanned: false)),
        SmartModeTextModelStatus.ready,
      );
    });

    test('a scanned, absent model is missing', () async {
      expect(
        await read(const SmartModeDownloadState()),
        SmartModeTextModelStatus.localModelMissing,
      );
    });

    test('a scanned, present model is ready', () async {
      expect(
        await read(const SmartModeDownloadState(modelDownloaded: true)),
        SmartModeTextModelStatus.ready,
      );
    });
  });

  group('smartModeTextModelStatus', () {
    SmartModeTextModelStatus local({
      bool engine = true,
      bool downloaded = true,
      String key = '',
    }) => smartModeTextModelStatus(
      provider: SmartModeProviderType.local,
      localEngineAvailable: engine,
      modelDownloaded: downloaded,
      openAiApiKey: key,
    );

    SmartModeTextModelStatus cloud({bool downloaded = true, String key = ''}) =>
        smartModeTextModelStatus(
          provider: SmartModeProviderType.openAI,
          localEngineAvailable: true,
          modelDownloaded: downloaded,
          openAiApiKey: key,
        );

    test('local provider with the model on disk is ready', () {
      expect(local(), SmartModeTextModelStatus.ready);
    });

    test('local provider without the downloaded model needs the model', () {
      expect(
        local(downloaded: false),
        SmartModeTextModelStatus.localModelMissing,
      );
    });

    test('local provider in a build without the bundled engine is '
        'unavailable even with the model on disk', () {
      expect(
        local(engine: false),
        SmartModeTextModelStatus.localEngineUnavailable,
      );
    });

    test('cloud provider with an API key is ready', () {
      expect(cloud(key: 'sk-test'), SmartModeTextModelStatus.ready);
    });

    test('cloud provider without a key needs a key, whatever is on disk', () {
      expect(cloud(downloaded: true), SmartModeTextModelStatus.cloudKeyMissing);
    });

    test('a whitespace-only key counts as no key', () {
      expect(cloud(key: '   '), SmartModeTextModelStatus.cloudKeyMissing);
    });
  });

  group('smartModeUnavailableReason and smartModeFixRowId', () {
    final l10n = lookupL10n(const Locale('en'));

    test('ready has no reason and no settings row to fix', () {
      expect(
        smartModeUnavailableReason(SmartModeTextModelStatus.ready, l10n),
        isNull,
      );
      expect(smartModeFixRowId(SmartModeTextModelStatus.ready), isNull);
    });

    test('missing local model points at the model download row', () {
      expect(
        smartModeUnavailableReason(
          SmartModeTextModelStatus.localModelMissing,
          l10n,
        ),
        l10n.smartModeNoTextModelHint,
      );
      expect(
        smartModeFixRowId(SmartModeTextModelStatus.localModelMissing),
        'text-smart-mode-model',
      );
    });

    test('missing cloud key points at the API key row', () {
      expect(
        smartModeFixRowId(SmartModeTextModelStatus.cloudKeyMissing),
        'text-smart-mode-key',
      );
    });

    test('an unavailable local engine names the build, not a download', () {
      expect(
        smartModeUnavailableReason(
          SmartModeTextModelStatus.localEngineUnavailable,
          l10n,
        ),
        l10n.smartModeLocalUnavailable,
      );
      expect(
        smartModeFixRowId(SmartModeTextModelStatus.localEngineUnavailable),
        isNull,
      );
    });
  });

  group('smartModeDeliveryOf', () {
    test('a confirmed paste is delivered', () {
      expect(
        smartModeDeliveryOf(paste: PasteOutcome.success, clipboardHeld: true),
        SmartModeDelivery.pasted,
      );
    });

    test('an unconfirmed paste is never reported as pasted', () {
      for (final outcome in [
        PasteOutcome.unconfirmed,
        PasteOutcome.unconfirmedNoBridge,
      ]) {
        expect(
          smartModeDeliveryOf(paste: outcome, clipboardHeld: true),
          SmartModeDelivery.unconfirmed,
          reason: '$outcome',
        );
      }
    });

    test('a refused or failed paste with the text on the clipboard is '
        'clipboard only', () {
      for (final outcome in [
        PasteOutcome.failed,
        PasteOutcome.blocked,
        PasteOutcome.permissionMissing,
        PasteOutcome.targetChanged,
      ]) {
        expect(
          smartModeDeliveryOf(paste: outcome, clipboardHeld: true),
          SmartModeDelivery.clipboard,
          reason: '$outcome',
        );
      }
    });

    test('no paste and no clipboard copy delivers nothing', () {
      expect(
        smartModeDeliveryOf(paste: PasteOutcome.failed, clipboardHeld: false),
        SmartModeDelivery.none,
      );
      expect(
        smartModeDeliveryOf(paste: null, clipboardHeld: false),
        SmartModeDelivery.none,
      );
    });

    test('copy-only action without a paste attempt is clipboard only', () {
      expect(
        smartModeDeliveryOf(paste: null, clipboardHeld: true),
        SmartModeDelivery.clipboard,
      );
    });
  });

  group('smartModeFallbackNoticeBody', () {
    final l10n = lookupL10n(const Locale('en'));

    test('no text model with a confirmed paste names the reason and says '
        'the raw text was pasted', () {
      expect(
        smartModeFallbackNoticeBody(
          l10n,
          reason: SmartModeFallbackReason.noTextModel,
          delivery: SmartModeDelivery.pasted,
        ),
        '${l10n.notificationSmartModeSkippedNoTextModel} '
        '${l10n.notificationSmartModeOutcomePasted}',
      );
    });

    test('a failed paste with the clipboard copy never says pasted', () {
      expect(
        smartModeFallbackNoticeBody(
          l10n,
          reason: SmartModeFallbackReason.failed,
          delivery: SmartModeDelivery.clipboard,
        ),
        '${l10n.notificationSmartModeSkippedBody} '
        '${l10n.notificationSmartModeOutcomeClipboard}',
      );
    });

    test('timeout reason uses the timeout sentence', () {
      expect(
        smartModeFallbackNoticeBody(
          l10n,
          reason: SmartModeFallbackReason.timedOut,
          delivery: SmartModeDelivery.none,
        ),
        startsWith(l10n.notificationSmartModeSkippedTimedOut),
      );
    });

    test(
      'every locale: each delivery gets its own sentence, so only a confirmed '
      'paste is ever described as pasted',
      () {
        for (final locale in L10n.supportedLocales) {
          final loc = lookupL10n(locale);
          for (final reason in SmartModeFallbackReason.values) {
            final reasonText = switch (reason) {
              SmartModeFallbackReason.noTextModel =>
                loc.notificationSmartModeSkippedNoTextModel,
              SmartModeFallbackReason.timedOut =>
                loc.notificationSmartModeSkippedTimedOut,
              SmartModeFallbackReason.failed =>
                loc.notificationSmartModeSkippedBody,
              // Without an endpoint code the generic body applies (see
              // customEndpointErrorText for the classed messages).
              SmartModeFallbackReason.customEndpoint =>
                loc.notificationSmartModeSkippedBody,
            };
            final expectedOutcome = {
              SmartModeDelivery.pasted: loc.notificationSmartModeOutcomePasted,
              SmartModeDelivery.unconfirmed:
                  loc.notificationSmartModeOutcomeUnconfirmed,
              SmartModeDelivery.clipboard:
                  loc.notificationSmartModeOutcomeClipboard,
              SmartModeDelivery.none: loc.notificationSmartModeOutcomeNone,
            };
            for (final delivery in SmartModeDelivery.values) {
              expect(
                smartModeFallbackNoticeBody(
                  loc,
                  reason: reason,
                  delivery: delivery,
                ),
                '$reasonText ${expectedOutcome[delivery]}',
                reason: '${locale.languageCode} $reason $delivery',
              );
            }
          }
        }
      },
    );
  });
}

class _Settings extends SettingsNotifier {
  @override
  // The default Smart Mode provider is the local one.
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _Download extends SmartModeDownloadNotifier {
  _Download(this._state);

  final SmartModeDownloadState _state;

  @override
  SmartModeDownloadState build() => _state;
}
