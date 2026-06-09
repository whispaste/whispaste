/// Unit tests for the MSIX child-process path de-virtualization core.
///
/// Regression coverage for FLUTTER_WHISPASTE-A0 (GTX 650 / Microsoft Store
/// build): the spawned, non-packaged whisper-server child does not inherit the
/// packaged parent's AppData redirection, so the virtualized `%APPDATA%`
/// model/binary path resolves to an empty real Roaming dir for the child
/// (`search path … does not exist` → exit 3). The fix rewrites child-facing
/// paths to the physical package-local LocalCache location.
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/path_service.dart';

// Maik's real machine — the package full name straight out of the diagnostics
// dump: `…\WindowsApps\<fullName>\whispaste.exe`.
const _msixExe =
    r'C:\Program Files\WindowsApps\12342SilvioLindstedt.WhisPaste'
    r'_1.2.36.0_x64__phagqa3gq04kr\whispaste.exe';
const _appData = r'C:\Users\maikg\AppData\Roaming';
const _localAppData = r'C:\Users\maikg\AppData\Local';

void main() {
  group('msixPackageFamilyFromExePath', () {
    test('derives family name (Name_PublisherId) from a WindowsApps path', () {
      expect(
        msixPackageFamilyFromExePath(_msixExe),
        '12342SilvioLindstedt.WhisPaste_phagqa3gq04kr',
      );
    });

    test('is case-insensitive on the WindowsApps marker', () {
      const exe =
          r'C:\Program Files\WINDOWSAPPS\Foo.Bar_1.0.0.0_x64__abc123\app.exe';
      expect(msixPackageFamilyFromExePath(exe), 'Foo.Bar_abc123');
    });

    test('returns null for a non-packaged (installer/portable) exe path', () {
      expect(
        msixPackageFamilyFromExePath(
          r'C:\Program Files\WhisPaste\whispaste.exe',
        ),
        isNull,
      );
    });

    test('tolerates forward slashes', () {
      const exe =
          'C:/Program Files/WindowsApps/Foo.Bar_1.0.0.0_x64__abc123/app.exe';
      expect(msixPackageFamilyFromExePath(exe), 'Foo.Bar_abc123');
    });
  });

  group('deVirtualizeMsixChildPathFor', () {
    test(
      'rewrites the model path under MSIX to the physical LocalCache path',
      () {
        const modelPath =
            r'C:\Users\maikg\AppData\Roaming\WhisPaste\models\stt'
            r'\ggml-small-q5_1.bin';

        expect(
          deVirtualizeMsixChildPathFor(
            path: modelPath,
            exePath: _msixExe,
            appData: _appData,
            localAppData: _localAppData,
          ),
          r'C:\Users\maikg\AppData\Local\Packages'
          r'\12342SilvioLindstedt.WhisPaste_phagqa3gq04kr'
          r'\LocalCache\Roaming\WhisPaste\models\stt\ggml-small-q5_1.bin',
        );
      },
    );

    test('rewrites the whisper-server binary path too', () {
      const serverPath =
          r'C:\Users\maikg\AppData\Roaming\WhisPaste\models\stt'
          r'\whisper-server.exe';

      expect(
        deVirtualizeMsixChildPathFor(
          path: serverPath,
          exePath: _msixExe,
          appData: _appData,
          localAppData: _localAppData,
        ),
        endsWith(
          r'\LocalCache\Roaming\WhisPaste\models\stt\whisper-server.exe',
        ),
      );
    });

    test('is a no-op for a non-MSIX (installer) build', () {
      const modelPath =
          r'C:\Users\maikg\AppData\Roaming\WhisPaste\models\stt'
          r'\ggml-small-q5_1.bin';

      expect(
        deVirtualizeMsixChildPathFor(
          path: modelPath,
          exePath: r'C:\Program Files\WhisPaste\whispaste.exe',
          appData: _appData,
          localAppData: _localAppData,
        ),
        modelPath,
      );
    });

    test('leaves paths outside the %APPDATA%\\WhisPaste root untouched', () {
      const elsewhere = r'C:\Users\maikg\AppData\Roaming\OtherApp\file.bin';
      expect(
        deVirtualizeMsixChildPathFor(
          path: elsewhere,
          exePath: _msixExe,
          appData: _appData,
          localAppData: _localAppData,
        ),
        elsewhere,
      );
    });

    test(
      'no-op when LOCALAPPDATA is missing (cannot build a physical path)',
      () {
        const modelPath = r'C:\Users\maikg\AppData\Roaming\WhisPaste\m.bin';
        expect(
          deVirtualizeMsixChildPathFor(
            path: modelPath,
            exePath: _msixExe,
            appData: _appData,
            localAppData: null,
          ),
          modelPath,
        );
      },
    );

    test('matches the AppData root case-insensitively', () {
      const modelPath =
          r'c:\users\maikg\appdata\roaming\whispaste\models\stt\m.bin';
      final result = deVirtualizeMsixChildPathFor(
        path: modelPath,
        exePath: _msixExe,
        appData: _appData,
        localAppData: _localAppData,
      );
      expect(result, contains(r'\LocalCache\Roaming\WhisPaste'));
      expect(result, endsWith(r'\models\stt\m.bin'));
    });
  });
}
