/// Unit tests for the MSIX child-process path de-virtualization core and the
/// MSIX standalone data-root discovery (Slice 1).
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

  // ---------------------------------------------------------------------------
  // msixLocalCacheCandidatesFor — pure path builder
  // ---------------------------------------------------------------------------

  group('msixLocalCacheCandidatesFor', () {
    test('returns candidates only for entries with the WhisPaste prefix', () {
      final candidates = msixLocalCacheCandidatesFor(
        localAppData: _localAppData,
        packageDirNames: [
          '12342SilvioLindstedt.WhisPaste_1.2.37.0_x64__phagqa3gq04kr',
          'Microsoft.WindowsStore_22306.1401.6.0_x64__8wekyb3d8bbwe',
          '12342SilvioLindstedt.WhisPaste_1.2.36.0_x64__phagqa3gq04kr',
        ],
      );
      expect(candidates, hasLength(2));
      expect(
        candidates.every(
          (c) => c.contains(r'\Packages\12342SilvioLindstedt.WhisPaste'),
        ),
        isTrue,
      );
      expect(
        candidates.every((c) => c.endsWith(r'\LocalCache\Roaming\WhisPaste')),
        isTrue,
      );
    });

    test('returns empty list when no WhisPaste entries are present', () {
      final candidates = msixLocalCacheCandidatesFor(
        localAppData: _localAppData,
        packageDirNames: [
          'Microsoft.WindowsStore_22306.1401.6.0_x64__8wekyb3d8bbwe',
          'Microsoft.Windows.Photos_2024.11090.15001.0_x64__8wekyb3d8bbwe',
        ],
      );
      expect(candidates, isEmpty);
    });

    test('is case-insensitive on the prefix match', () {
      final candidates = msixLocalCacheCandidatesFor(
        localAppData: _localAppData,
        packageDirNames: [
          '12342SILVIOLINDSTEDT.WHISPASTE_1.2.37.0_x64__phagqa3gq04kr',
        ],
      );
      expect(candidates, hasLength(1));
    });

    test('returns empty list for empty package dir names', () {
      final candidates = msixLocalCacheCandidatesFor(
        localAppData: _localAppData,
        packageDirNames: const [],
      );
      expect(candidates, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // selectMsixDataRoot — pure selection function (table tests, AC3)
  // ---------------------------------------------------------------------------

  group('selectMsixDataRoot', () {
    const rootA =
        r'C:\Users\maikg\AppData\Local\Packages'
        r'\12342SilvioLindstedt.WhisPaste_1.2.36.0_x64__phagqa3gq04kr'
        r'\LocalCache\Roaming\WhisPaste';

    const rootB =
        r'C:\Users\maikg\AppData\Local\Packages'
        r'\12342SilvioLindstedt.WhisPaste_1.2.37.0_x64__phagqa3gq04kr'
        r'\LocalCache\Roaming\WhisPaste';

    test('returns the matching candidate when exactly one has models\\stt', () {
      final result = selectMsixDataRoot([
        rootA,
        rootB,
      ], hasSttSubdir: (root) => root == rootB);
      expect(result, rootB);
    });

    test('returns null when no candidate has models\\stt', () {
      final result = selectMsixDataRoot([
        rootA,
        rootB,
      ], hasSttSubdir: (_) => false);
      expect(result, isNull);
    });

    test('returns null when candidates list is empty', () {
      final result = selectMsixDataRoot(const [], hasSttSubdir: (_) => true);
      expect(result, isNull);
    });

    test('when multiple candidates match, returns the first in list order '
        '(deterministic choice)', () {
      final result = selectMsixDataRoot(
        [rootA, rootB],
        hasSttSubdir: (_) => true, // both match
      );
      expect(result, rootA); // first wins
    });

    test('single candidate that matches is returned directly', () {
      final result = selectMsixDataRoot([
        rootA,
      ], hasSttSubdir: (root) => root == rootA);
      expect(result, rootA);
    });

    test('single candidate that does not match returns null', () {
      final result = selectMsixDataRoot([rootA], hasSttSubdir: (_) => false);
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // collectAllDataRoots — pure multi-root collector (table tests, AC1–AC4)
  // ---------------------------------------------------------------------------

  group('collectAllDataRoots', () {
    const exeRoot = r'C:\Users\maikg\AppData\Roaming\WhisPaste';

    const msixRoot1 =
        r'C:\Users\maikg\AppData\Local\Packages'
        r'\12342SilvioLindstedt.WhisPaste_1.2.36.0_x64__phagqa3gq04kr'
        r'\LocalCache\Roaming\WhisPaste';

    const msixRoot2 =
        r'C:\Users\maikg\AppData\Local\Packages'
        r'\12342SilvioLindstedt.WhisPaste_1.2.37.0_x64__phagqa3gq04kr'
        r'\LocalCache\Roaming\WhisPaste';

    // AC4: no roots at all.
    test('returns empty list when no root has models\\stt', () {
      final result = collectAllDataRoots(
        exeDataRoot: exeRoot,
        msixCandidates: [msixRoot1, msixRoot2],
        hasSttSubdir: (_) => false,
      );
      expect(result, isEmpty);
    });

    test('returns empty list when exeDataRoot is null and no MSIX match', () {
      final result = collectAllDataRoots(
        exeDataRoot: null,
        msixCandidates: [msixRoot1],
        hasSttSubdir: (_) => false,
      );
      expect(result, isEmpty);
    });

    // AC1: EXE + MSIX coexist.
    test('AC1: both EXE and MSIX roots present → both returned, EXE first', () {
      final result = collectAllDataRoots(
        exeDataRoot: exeRoot,
        msixCandidates: [msixRoot1],
        hasSttSubdir: (_) => true,
      );
      expect(result, hasLength(2));
      expect(
        result[0],
        const DataRootEntry(root: exeRoot, label: 'EXE-Installer'),
      );
      expect(
        result[1],
        const DataRootEntry(root: msixRoot1, label: 'Microsoft Store / MSIX'),
      );
    });

    // AC2: multiple MSIX roots all listed.
    test('AC2: two MSIX candidates both matching → both returned in order', () {
      final result = collectAllDataRoots(
        exeDataRoot: null,
        msixCandidates: [msixRoot1, msixRoot2],
        hasSttSubdir: (_) => true,
      );
      expect(result, hasLength(2));
      expect(
        result[0],
        const DataRootEntry(root: msixRoot1, label: 'Microsoft Store / MSIX'),
      );
      expect(
        result[1],
        const DataRootEntry(root: msixRoot2, label: 'Microsoft Store / MSIX'),
      );
    });

    // AC3: deterministic order (EXE before MSIX; MSIX in candidate list order).
    test(
      'AC3: order is deterministic — EXE before MSIX, MSIX in list order',
      () {
        // All three match; verify the canonical ordering.
        final result = collectAllDataRoots(
          exeDataRoot: exeRoot,
          msixCandidates: [msixRoot2, msixRoot1], // deliberately reversed
          hasSttSubdir: (_) => true,
        );
        expect(result, hasLength(3));
        expect(result[0].label, 'EXE-Installer');
        expect(result[1].root, msixRoot2); // candidate list order preserved
        expect(result[2].root, msixRoot1);
      },
    );

    test('AC3: single MSIX match is the only result (no EXE)', () {
      final result = collectAllDataRoots(
        exeDataRoot: null,
        msixCandidates: [msixRoot1, msixRoot2],
        hasSttSubdir: (r) => r == msixRoot2,
      );
      expect(result, hasLength(1));
      expect(result[0].root, msixRoot2);
      expect(result[0].label, 'Microsoft Store / MSIX');
    });

    test('only EXE matches → single EXE entry returned', () {
      final result = collectAllDataRoots(
        exeDataRoot: exeRoot,
        msixCandidates: [msixRoot1, msixRoot2],
        hasSttSubdir: (r) => r == exeRoot,
      );
      expect(result, hasLength(1));
      expect(
        result[0],
        const DataRootEntry(root: exeRoot, label: 'EXE-Installer'),
      );
    });

    test('empty MSIX candidates + EXE present → only EXE returned', () {
      final result = collectAllDataRoots(
        exeDataRoot: exeRoot,
        msixCandidates: const [],
        hasSttSubdir: (_) => true,
      );
      expect(result, hasLength(1));
      expect(result[0].label, 'EXE-Installer');
    });

    test('DataRootEntry equality and hashCode', () {
      const a = DataRootEntry(root: exeRoot, label: 'EXE-Installer');
      const b = DataRootEntry(root: exeRoot, label: 'EXE-Installer');
      const c = DataRootEntry(root: msixRoot1, label: 'Microsoft Store / MSIX');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
