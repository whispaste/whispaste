/// Standalone debug entrypoint for the Smart-Mode-v2 sandbox prototype —
/// NOT wired into the production app (see main.dart), following the same
/// separate-entrypoint pattern as floating_button_render_entrypoint.dart.
/// Kept fully isolated from production code paths on purpose: this exists
/// only to exercise [SmartModeFfiEngine] inside a real, signed, sandboxed
/// `.app` bundle built via the "Runner (MAS)" scheme — the thing an
/// unsandboxed CLI smoke test cannot prove (App Sandbox library-validation,
/// container file-path resolution, entitlement gaps).
///
/// Run/build via the normal Flutter macOS toolchain, e.g.:
///   flutter run -t lib/main_smart_mode_debug.dart -d macos
///
/// MANDATORY for any MAS-scheme validation build: override the bundle
/// identifier so this throwaway build is NEVER registered under the
/// production `de.whispaste.app` identity. Building/running it under the
/// real bundle ID pollutes Launch Services' CFBundleIdentifier ->
/// path resolution (`lsregister`) with a second, throwaway candidate — the
/// real, currently-running production app can then have its own
/// relaunch/focus/activation calls resolve to the wrong (test) bundle
/// instead of `/Applications/WhisPaste.app` (confirmed via `mdfind
/// "kMDItemCFBundleIdentifier == 'de.whispaste.app'"` after one test build
/// — 5 candidates, ambiguity real, not hypothetical). Always build with:
///   xcodebuild -workspace macos/Runner.xcworkspace -scheme "Runner (MAS)" \
///     -configuration MAS build \
///     PRODUCT_BUNDLE_IDENTIFIER=de.whispaste.smartmode.debug
/// and delete the resulting throwaway `.app` (or at minimum re-run
/// `lsregister -f /Applications/WhisPaste.app` afterward) once done — never
/// leave a same-bundle-ID test copy sitting registered.
library;

import 'package:flutter/material.dart';

import 'services/smart_mode/smart_mode_ffi_engine.dart';

void main() {
  runApp(const _SmartModeDebugApp());
}

class _SmartModeDebugApp extends StatelessWidget {
  const _SmartModeDebugApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Smart-Mode-v2 Debug',
      home: _SmartModeDebugScreen(),
    );
  }
}

const _cleanupSystemPrompt =
    'Bereinige diesen diktierten deutschen Text: entferne Füllwörter (äh, '
    'ähm, also), korrigiere Interpunktion und Groß-/Kleinschreibung. Ändere '
    'Inhalt und Wortwahl NICHT. Gib NUR den bereinigten Text aus, keine '
    'Erklärung.';

const _testInput =
    'ich äh wollte nur fragen ob du mir bis Freitag noch die Zahlen '
    'schicken kannst weil ähm ich die für das Kunden-Meeting brauche';

class _SmartModeDebugScreen extends StatefulWidget {
  const _SmartModeDebugScreen();

  @override
  State<_SmartModeDebugScreen> createState() => _SmartModeDebugScreenState();
}

class _SmartModeDebugScreenState extends State<_SmartModeDebugScreen> {
  String _status = 'Bereit.';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    // Auto-run once on launch — lets a headless direct-binary smoke test
    // (no UI interaction possible) still exercise the full sandboxed path
    // by grepping stdout for the SMART_MODE_TEST_RESULT marker below.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTest());
  }

  Future<void> _runTest() async {
    setState(() {
      _running = true;
      _status = 'Lade Modell + generiere … (kann einige Sekunden dauern)';
    });
    final stopwatch = Stopwatch()..start();
    try {
      final engine = SmartModeFfiEngine();
      final result = await engine.run(
        systemPrompt: _cleanupSystemPrompt,
        userText: _testInput,
      );
      setState(() {
        _status =
            'OK (${stopwatch.elapsedMilliseconds}ms)\n\n'
            'IN:  $_testInput\n\n'
            'OUT: $result';
      });
      // Debug-only entrypoint with no UI access in a headless smoke test —
      // stdout is the only channel to check the result.
      // ignore: avoid_print
      print(
        'SMART_MODE_TEST_RESULT: OK ${stopwatch.elapsedMilliseconds}ms out=$result',
      );
    } catch (e) {
      setState(() {
        _status = 'FEHLER: $e';
      });
      // Debug-only entrypoint, see rationale on the OK-path print above.
      // ignore: avoid_print
      print('SMART_MODE_TEST_RESULT: FAIL $e');
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart-Mode-v2 Sandbox-Prototyp')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runTest,
              child: Text(_running ? 'Läuft …' : 'Cleanup-Test ausführen'),
            ),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: Text(_status))),
          ],
        ),
      ),
    );
  }
}
