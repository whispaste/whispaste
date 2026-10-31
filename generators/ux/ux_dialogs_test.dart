/// Survey of the dialog shapes on the shared footer (`lib/widgets/dialog.dart`,
/// `lib/COMPONENTS.md` "Dialogs"): a destructive confirm (row), a choice over
/// the first-run setup (stack, hero CTA), the out-of-memory choice (stack),
/// the PIN form and the CUDA licence (deliberate consent). Asserts nothing:
/// layout exceptions go to exceptions.log, PNGs to the output dir. Tagged
/// `ux-screens`, never run in CI.
///
///   `UX_SCREENS_DIR=OUT_DIR wp-test.sh run WORKTREE --host ubu generators/ux/ux_dialogs_test.dart`
@Tags(<String>['ux-screens'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_pin_dialogs.dart';
import 'package:whispaste/features/settings/sections/cuda_eula_dialog.dart';
import 'package:whispaste/widgets/dialog.dart';
import 'package:whispaste/widgets/oom_recovery_dialog.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<String> _themes = ['navy', 'dark'];
const String _locale = 'de';

enum _Dialog { deleteConfirm, setupClose, outOfMemory, pinUnlock, cudaLicence }

void _open(BuildContext context, _Dialog dialog) {
  final l10n = L10n.of(context);
  switch (dialog) {
    case _Dialog.deleteConfirm:
      unawaited(
        showWpConfirmDialog(
          context: context,
          title: l10n.historyEmptyTrash,
          message: l10n.unsavedInputMessage,
          confirmLabel: l10n.historyEmptyTrash,
          cancelLabel: l10n.actionCancel,
          destructive: true,
        ),
      );
    case _Dialog.setupClose:
      // The onboarding close dialog lives on the onboarding branch; this is
      // its shape with its German copy.
      unawaited(
        showWpChoiceDialog<int>(
          context: context,
          title: 'Einrichtung pausieren oder WhisPaste beenden?',
          body:
              'Pausiert bleibt WhisPaste in der Menüleiste. Dort setzt du die '
              'Einrichtung später an derselben Stelle fort.',
          cta: WpDialogCta.hero,
          dismissValue: 0,
          choices: [
            const WpDialogAction(
              label: 'Einrichtung fortsetzen',
              testId: 'ux-close-continue',
              role: WpDialogActionRole.primary,
              value: 0,
            ),
            const WpDialogAction(
              label: 'Einrichtung pausieren',
              testId: 'ux-close-pause',
              value: 1,
            ),
            WpDialogAction(
              label: l10n.trayQuit,
              testId: 'ux-close-quit',
              role: WpDialogActionRole.destructiveExit,
              value: 2,
            ),
          ],
        ),
      );
    case _Dialog.outOfMemory:
      unawaited(
        showWpOomRecoveryDialog(
          context: context,
          l10n: l10n,
          modelName: 'Whisper Large v3 Turbo',
          hasCloudConfigured: true,
          isPermanentFail: false,
          cloudProviderName: 'OpenAI',
        ),
      );
    case _Dialog.pinUnlock:
      unawaited(showHistoryPinUnlockDialog(context, offerForgot: true));
    case _Dialog.cudaLicence:
      unawaited(showCudaEulaDialog(context));
  }
}

/// Hosts its own [Navigator] inside the capture boundary, so the dialog route
/// is painted inside the PNG.
class _DialogProbe extends StatelessWidget {
  const _DialogProbe({required this.dialog});

  final _Dialog dialog;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => _OpenOnFrame(dialog: dialog)),
  );
}

class _OpenOnFrame extends StatefulWidget {
  const _OpenOnFrame({required this.dialog});

  final _Dialog dialog;

  @override
  State<_OpenOnFrame> createState() => _OpenOnFrameState();
}

class _OpenOnFrameState extends State<_OpenOnFrame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(context, widget.dialog);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _capture(WidgetTester tester, String outDir, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  Directory(outDir).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey(kUxCaptureKey)),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final dialog in _Dialog.values) {
    for (final theme in _themes) {
      final name = 'dialog-${dialog.name}__${theme}_$_locale';
      testWidgets('ux-dialogs: $name', (tester) async {
        final db = await openSeededUxDatabase(tester);
        addTearDown(() => tester.runAsync(db.close));

        await pumpUxScreen(
          tester,
          screen: UxScreen(
            id: 'dialog-${dialog.name}',
            activePageId: 'history',
            build: () => _DialogProbe(dialog: dialog),
          ),
          db: db,
          size: kUxSize1100,
          scale: 1.0,
          theme: theme,
          locale: _locale,
        );
        await _capture(tester, outDir, name);

        final error = tester.takeException();
        if (error != null) {
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/exceptions.log',
          ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
