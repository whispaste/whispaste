import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/paste/paste_setup_hint.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/tray_service.dart';

import '../../test_helpers/paste_notice_fakes.dart';

/// Keeps the click target, which [RecordingSystemAttention] drops.
class _ClickRecordingAttention extends RecordingSystemAttention {
  _ClickRecordingAttention(super.ref);

  final clicks = <void Function()?>[];

  @override
  Future<bool> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
    bool showNotification = true,
  }) async {
    clicks.add(onClick);
    return super.requestAttention(kind: kind, title: title, body: body);
  }
}

void main() {
  late ProviderContainer container;
  late FakeNoticeTray tray;

  const clipboardOnly = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'clipboard',
    ),
    onboarding: OnboardingSettings(onboardingCompleted: true),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tray = FakeNoticeTray();
    container = ProviderContainer(
      overrides: [
        trayServiceProvider.overrideWith(() => tray),
        systemAttentionServiceProvider.overrideWith(
          _ClickRecordingAttention.new,
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  _ClickRecordingAttention attention() =>
      container.read(systemAttentionServiceProvider)
          as _ClickRecordingAttention;

  test('posts once, quietly, and the click opens the paste setting', () async {
    final hint = container.read(pasteSetupHintProvider);

    expect(await hint.afterClipboardOnly(clipboardOnly), isTrue);
    expect(await hint.afterClipboardOnly(clipboardOnly), isFalse);

    expect(attention().requests.map((r) => r.kind), [
      AttentionKind.pasteSetupHint,
    ]);
    attention().clicks.single!();
    expect(tray.openedActionNeededKeys, [kTrayPasteActionNeededKey]);
    // Information only: no tray entry.
    expect(tray.setActionNeededLabels, isEmpty);
  });

  test('a notice the OS did not show is offered again', () async {
    final hint = container.read(pasteSetupHintProvider);
    attention().delivers = false;

    expect(await hint.afterClipboardOnly(clipboardOnly), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPasteSetupHintShownKey), isNull);

    attention().delivers = true;
    expect(await hint.afterClipboardOnly(clipboardOnly), isTrue);
    expect(prefs.getBool(kPasteSetupHintShownKey), isTrue);
    expect(attention().requests, hasLength(2));
  });

  test('a new app session does not post it again', () async {
    await container
        .read(pasteSetupHintProvider)
        .afterClipboardOnly(clipboardOnly);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        trayServiceProvider.overrideWith(() => tray),
        systemAttentionServiceProvider.overrideWith(
          _ClickRecordingAttention.new,
        ),
      ],
    );

    expect(
      await container
          .read(pasteSetupHintProvider)
          .afterClipboardOnly(clipboardOnly),
      isFalse,
    );
    expect(attention().requests, isEmpty);
  });

  test('a closed "Auto-Paste off" chip ends the hint', () async {
    const dismissed = AppSettings(
      afterTranscriptionSection: AfterTranscriptionSettings(
        afterTranscription: 'clipboard',
      ),
      onboarding: OnboardingSettings(
        onboardingCompleted: true,
        autoPasteOffHintDismissed: true,
      ),
    );

    expect(
      await container
          .read(pasteSetupHintProvider)
          .afterClipboardOnly(dismissed),
      isFalse,
    );
    expect(attention().requests, isEmpty);
  });
}
