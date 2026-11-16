import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_errors.dart';
import 'package:whispaste/services/smart_mode/smart_mode_text_model.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('transcription and Smart Mode codes of one class share one message', () {
    expect(
      customEndpointErrorText(l10n, 'custom_endpoint_unreachable'),
      l10n.errorCustomEndpointUnreachable,
    );
    expect(
      customEndpointErrorText(l10n, 'smart_mode_custom_unreachable'),
      l10n.errorCustomEndpointUnreachable,
    );
    expect(
      customEndpointErrorText(l10n, 'smart_mode_custom_timeout'),
      l10n.errorCustomEndpointUnreachable,
    );
    expect(
      customEndpointErrorText(l10n, 'custom_model_missing'),
      customEndpointErrorText(l10n, 'smart_mode_custom_model_missing'),
    );
    expect(
      customEndpointErrorText(l10n, 'custom_bad_response'),
      customEndpointErrorText(l10n, 'smart_mode_custom_bad_format'),
    );
  });

  test('every Smart Mode endpoint class has its own message', () {
    expect(
      customEndpointErrorText(l10n, 'smart_mode_custom_not_configured'),
      l10n.errorCustomEndpointNotConfigured,
    );
    expect(
      customEndpointErrorText(l10n, 'smart_mode_custom_unauthorized'),
      l10n.errorCustomEndpointUnauthorized,
    );
    expect(
      customEndpointErrorText(l10n, 'smart_mode_custom_server_error'),
      l10n.errorCustomEndpointServerError,
    );
  });

  test('unknown or foreign codes get no endpoint message', () {
    expect(customEndpointErrorText(l10n, ''), isNull);
    expect(customEndpointErrorText(l10n, 'openai_rate_limited'), isNull);
    expect(customEndpointErrorText(l10n, 'smart_mode_custom_unknown'), isNull);
  });

  test(
    'a Smart Mode endpoint fallback names its class, not the generic body',
    () {
      final body = smartModeFallbackNoticeBody(
        l10n,
        reason: SmartModeFallbackReason.customEndpoint,
        delivery: SmartModeDelivery.clipboard,
        customEndpointCode: 'smart_mode_custom_unauthorized',
      );
      expect(
        body,
        '${l10n.errorCustomEndpointUnauthorized} '
        '${l10n.notificationSmartModeOutcomeClipboard}',
      );
    },
  );

  test(
    'an unknown endpoint code falls back to the generic Smart Mode body',
    () {
      expect(
        smartModeFallbackNoticeBody(
          l10n,
          reason: SmartModeFallbackReason.customEndpoint,
          delivery: SmartModeDelivery.none,
        ),
        '${l10n.notificationSmartModeSkippedBody} '
        '${l10n.notificationSmartModeOutcomeNone}',
      );
    },
  );
}
