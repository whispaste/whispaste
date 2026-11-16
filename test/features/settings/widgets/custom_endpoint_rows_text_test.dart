import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/widgets/custom_endpoint_rows.dart';
import 'package:whispaste/services/custom_endpoint/custom_endpoint_probe.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  test('the network notice says where the audio goes', () {
    expect(
      customEndpointNoticeText(
        l10n,
        Uri.parse('http://localhost:1234/v1'),
        scope: CustomEndpointScope.speech,
      ),
      l10n.customEndpointNoticeLocal,
    );
    expect(
      customEndpointNoticeText(
        l10n,
        Uri.parse('https://llm.example.com/v1'),
        scope: CustomEndpointScope.speech,
      ),
      'Audio is sent to llm.example.com.',
    );
  });

  test('the Smart Mode notice names the text, not the audio', () {
    expect(
      customEndpointNoticeText(
        l10n,
        Uri.parse('https://llm.example.com/v1'),
        scope: CustomEndpointScope.smartMode,
      ),
      'Transcribed text is sent to llm.example.com.',
    );
  });

  test('the notice has three levels: device, local network, internet host', () {
    expect(
      customEndpointNoticeText(
        l10n,
        Uri.parse('http://192.168.1.20:1234/v1'),
        scope: CustomEndpointScope.speech,
      ),
      l10n.customEndpointNoticeLan,
    );
    expect(l10n.customEndpointNoticeLocal, 'Stays on this device.');
    expect(l10n.customEndpointNoticeLan, 'Stays in your local network.');
  });

  test('a refused address gets its message, an empty field none', () {
    expect(customEndpointUrlProblemText(l10n, ''), isNull);
    expect(
      customEndpointUrlProblemText(l10n, 'http://8.8.8.8/v1'),
      l10n.customEndpointUrlHttpRemote,
    );
    expect(
      customEndpointUrlProblemText(l10n, 'http://192.168.1.20/v1'),
      isNull,
    );
    expect(customEndpointUrlProblemText(l10n, 'https://localhost/v1'), isNull);
  });

  test('each probe result has its own message', () {
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(
          CustomEndpointProbeResult.connected,
          modelVerified: true,
        ),
      ),
      l10n.customEndpointProbeConnected,
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(CustomEndpointProbeResult.connected),
      ),
      l10n.customEndpointProbeConnectedUnverified,
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(
          CustomEndpointProbeResult.modelMissing,
          availableModels: ['qwen', 'gemma'],
        ),
      ),
      l10n.customEndpointProbeModelMissing('qwen, gemma'),
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(CustomEndpointProbeResult.unreachable),
      ),
      l10n.customEndpointProbeUnreachable,
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(CustomEndpointProbeResult.unauthorized),
      ),
      l10n.customEndpointProbeUnauthorized,
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(CustomEndpointProbeResult.badFormat),
      ),
      l10n.customEndpointProbeBadFormat,
    );
    expect(
      customEndpointProbeText(
        l10n,
        const CustomEndpointProbe(CustomEndpointProbeResult.serverError),
      ),
      l10n.customEndpointProbeServerError,
    );
  });
}
