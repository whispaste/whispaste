import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';

/// Controller that also reports the focused field's type (#948, Windows).
class ProbingPasteController
    implements DesktopPasteController, FocusedFieldTypeProbe {
  ProbingPasteController(this.answer);

  /// What the probe answers; a never-completing future simulates a hung
  /// target, a throwing one a broken channel.
  Future<FocusedFieldType> Function() answer;
  int probeCalls = 0;
  int pasteCalls = 0;
  int typeCalls = 0;

  @override
  Future<FocusedFieldType> focusedFieldType() {
    probeCalls++;
    return answer();
  }

  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls++;
    return const NativePasteResult(status: NativePasteStatus.success);
  }

  @override
  Future<NativePasteResult> copySelection({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.unknown);

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async {
    typeCalls++;
    return const NativePasteResult(status: NativePasteStatus.success);
  }

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async => false;

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<void> dispose() async {}
}
