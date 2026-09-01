/// Standalone debug entrypoint for the Smart-Mode-v2 sandbox prototype —
/// NOT wired into the production app (see main.dart), following the same
/// separate-entrypoint pattern as floating_button_render_entrypoint.dart.
/// Kept fully isolated from production code paths on purpose: this exists
/// only to exercise [SmartModeFfiEngine] inside a real, signed, sandboxed
/// `.app` bundle built via the "Runner (MAS)" scheme — the thing an
/// unsandboxed CLI smoke test cannot prove (App Sandbox library-validation,
/// container file-path resolution, entitlement gaps). Interactive on
/// purpose (paste a real dictation, pick a preset, see the exact system
/// prompt and real elapsed time) — the point is to let the maintainer feel
/// the real Smart-Mode UX, not just prove a marker string round-trips.
///
/// MANDATORY every time — keeps this side by side with the real,
/// currently-installed WhisPaste without any confusion or interference:
///   PRODUCT_BUNDLE_IDENTIFIER=de.whispaste.smartmode.debug — a distinct
///   bundle ID. (macos/embed_libllama.sh now embeds the llama.cpp dylibs
///   unconditionally for every build of the "Runner" target, Smart Mode
///   prototype or real app alike — no env var needed for that anymore.)
///
///   xcodebuild \
///     -workspace macos/Runner.xcworkspace -scheme "Runner (MAS)" \
///     -configuration MAS build \
///     PRODUCT_BUNDLE_IDENTIFIER=de.whispaste.smartmode.debug
///
/// Skipping the bundle-ID override pollutes Launch Services' identifier ->
/// path resolution for the REAL `de.whispaste.app` (confirmed: multiple
/// candidate paths for one bundle ID after a single test build) — the real,
/// running production app's own relaunch/focus calls can then resolve to this
/// throwaway build instead of `/Applications/WhisPaste.app`.
///
/// Do NOT pass `PRODUCT_NAME=...` on the xcodebuild command line: it is global
/// across the whole workspace and makes every Pod sub-target (Sentry,
/// url_launcher_macos, record_macos, …) try to build itself under that name,
/// breaking the build. The window title is already handled by window_manager
/// below (so both windows look distinct), and if you also want a distinct Dock
/// name, patch CFBundleName in the BUILT `.app` afterwards with PlistBuddy —
/// never via PRODUCT_NAME. Delete the throwaway `.app` (or re-run
/// `lsregister -f /Applications/WhisPaste.app`) once done.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/smart_mode/smart_mode_ffi_engine.dart';
import 'widgets/wp_button.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The window title bar text comes from window_manager's WindowOptions
  // (see main.dart's _initDesktopWindow), NOT from Info.plist's
  // CFBundleName/CFBundleDisplayName — patching those post-build left the
  // title bar showing the OS-default fallback ("WhisPaste", same as the
  // real app), making the two builds visually indistinguishable even with
  // fully separate bundle IDs. Set it explicitly here.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(title: 'WhisPaste SmartMode Debug'),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const _SmartModeDebugApp());
}

class _SmartModeDebugApp extends StatelessWidget {
  const _SmartModeDebugApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'WhisPaste SmartMode Debug',
      home: _SmartModeDebugScreen(),
    );
  }
}

enum _Preset { cleanup, concise, translate }

// Identical wording to the already spike-tested presets
// (.scratch/smart-mode-v2/run_batch_test.py) — same prompts, same config,
// so trying it here is representative of the real feature, not a rewrite.
const _systemPrompts = {
  _Preset.cleanup:
      'Bereinige diesen diktierten deutschen Text: entferne Füllwörter (äh, '
      'ähm, also), korrigiere Interpunktion und Groß-/Kleinschreibung. Ändere '
      'Inhalt und Wortwahl NICHT. Gib NUR den bereinigten Text aus, keine '
      'Erklärung.',
  _Preset.concise:
      'Fasse diesen diktierten deutschen Text kürzer und prägnanter, ohne die '
      'Kernaussage zu verändern. Gib NUR den gekürzten Text aus, keine '
      'Erklärung.',
  _Preset.translate:
      'Übersetze diesen deutschen Text ins Englische. Gib NUR die '
      'Übersetzung aus, keine Erklärung.',
};

const _presetLabels = {
  _Preset.cleanup: 'Cleanup',
  _Preset.concise: 'Concise',
  _Preset.translate: 'Translate (DE→EN)',
};

class _SmartModeDebugScreen extends StatefulWidget {
  const _SmartModeDebugScreen();

  @override
  State<_SmartModeDebugScreen> createState() => _SmartModeDebugScreenState();
}

class _SmartModeDebugScreenState extends State<_SmartModeDebugScreen> {
  final _inputController = TextEditingController();
  _Preset _preset = _Preset.cleanup;
  String _output = '';
  int? _elapsedMs;
  String? _error;
  bool _running = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final userText = _inputController.text.trim();
    if (userText.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _output = '';
      _elapsedMs = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final engine = SmartModeFfiEngine();
      final result = await engine.run(
        systemPrompt: _systemPrompts[_preset]!,
        userText: userText,
      );
      setState(() {
        _output = result;
        _elapsedMs = stopwatch.elapsedMilliseconds;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _elapsedMs = stopwatch.elapsedMilliseconds;
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhisPaste SmartMode — Sandbox-Prototyp'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Eigenes Diktat einfügen (z. B. aus der echten WhisPaste-App kopiert):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inputController,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Diktierten Text hier einfügen …',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Preset: '),
                const SizedBox(width: 8),
                DropdownButton<_Preset>(
                  value: _preset,
                  items: _Preset.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(_presetLabels[p]!),
                        ),
                      )
                      .toList(),
                  onChanged: _running
                      ? null
                      : (p) => setState(() => _preset = p!),
                ),
                const SizedBox(width: 16),
                WpButton(
                  label: _running ? 'Läuft …' : 'Verarbeiten',
                  variant: WpButtonVariant.primary,
                  onPressed: _running ? null : _run,
                  isLoading: _running,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Tatsächlich verwendeter System-Prompt:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                _systemPrompts[_preset]!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            if (_elapsedMs != null)
              Text(
                'Dauer: ${_elapsedMs}ms',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _error != null ? 'FEHLER: $_error' : _output,
                  style: TextStyle(color: _error != null ? Colors.red : null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
