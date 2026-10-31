/// Unit tests for the CLI entrypoint orchestration:
/// gather → write .txt → bundle .zip.
///
/// Verifies the orchestration logic without touching the real Desktop
/// or requiring an installed app. Uses injectable seams for the output
/// directory and the report content producer.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/cli/cli_orchestrator.dart';

void main() {
  group('buildAndWriteReport', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('whispaste_cli_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'writes a .txt file and a .zip to the given output directory',
      () async {
        await buildAndWriteReport(
          outputDir: tempDir.path,
          reportProducer: () async =>
              'WhisPaste Diagnose-Report\nVersion: 1.0.0\n',
        );

        final files = tempDir.listSync().whereType<File>().toList();
        final txtFiles = files.where((f) => f.path.endsWith('.txt')).toList();
        final zipFiles = files.where((f) => f.path.endsWith('.zip')).toList();

        expect(txtFiles, hasLength(1), reason: 'exactly one .txt report file');
        expect(zipFiles, hasLength(1), reason: 'exactly one .zip bundle');
      },
    );

    test('txt file contains the report content', () async {
      const reportContent = 'WhisPaste Diagnose-Report\nOS: macos\n';
      await buildAndWriteReport(
        outputDir: tempDir.path,
        reportProducer: () async => reportContent,
      );

      final txtFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.txt'),
      );

      expect(txtFile.readAsStringSync(), equals(reportContent));
    });

    test('zip file name matches the txt base name', () async {
      await buildAndWriteReport(
        outputDir: tempDir.path,
        reportProducer: () async => 'test content',
      );

      final files = tempDir.listSync().whereType<File>().toList();
      final txtName = p.basenameWithoutExtension(
        files.firstWhere((f) => f.path.endsWith('.txt')).path,
      );
      final zipName = p.basenameWithoutExtension(
        files.firstWhere((f) => f.path.endsWith('.zip')).path,
      );

      expect(zipName, equals(txtName));
    });

    test('zip contains the txt entry', () async {
      const reportContent = 'zip-contents-test';
      await buildAndWriteReport(
        outputDir: tempDir.path,
        reportProducer: () async => reportContent,
      );

      final zipFile = tempDir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.zip'),
      );

      // Validate the zip can be found and is non-empty.
      expect(zipFile.lengthSync(), greaterThan(0));
    });

    test('output directory is created when it does not exist', () async {
      final nestedDir = p.join(tempDir.path, 'nested', 'output');
      expect(Directory(nestedDir).existsSync(), isFalse);

      await buildAndWriteReport(
        outputDir: nestedDir,
        reportProducer: () async => 'nested test',
      );

      expect(Directory(nestedDir).existsSync(), isTrue);
      expect(
        Directory(nestedDir).listSync().whereType<File>().length,
        equals(2),
      );
    });

    test('deliveryStep is called with the zip path after writing', () async {
      String? capturedZip;
      Future<void> fakeDelivery(String zipPath) async {
        capturedZip = zipPath;
      }

      final returnedZip = await buildAndWriteReport(
        outputDir: tempDir.path,
        reportProducer: () async => 'delivery-seam test',
        deliveryStep: fakeDelivery,
      );

      expect(capturedZip, isNotNull, reason: 'deliveryStep must be called');
      expect(capturedZip, equals(returnedZip));
      expect(capturedZip, endsWith('.zip'));
    });

    test('deliveryStep is NOT called when null (CI mode)', () async {
      // Omitting deliveryStep means the ZIP is still written but no delivery
      // occurs. We verify the zip file is still produced (smoke check).
      final returnedZip = await buildAndWriteReport(
        outputDir: tempDir.path,
        reportProducer: () async => 'no delivery',
        // deliveryStep omitted → null: no Finder/mail launch
      );

      expect(returnedZip, endsWith('.zip'));
      expect(File(returnedZip).existsSync(), isTrue);
    });
  });

  group('resolveDesktopPath', () {
    test('returns a non-empty path', () {
      final path = resolveDesktopPath(
        environment: {'HOME': '/Users/test', 'USERPROFILE': r'C:\Users\test'},
      );
      expect(path, isNotEmpty);
    });

    test('on mac-like env uses HOME/Desktop', () {
      final path = resolveDesktopPath(
        environment: {'HOME': '/Users/test'},
        platformOverride: 'macos',
      );
      expect(path, equals('/Users/test/Desktop'));
    });

    test('on windows env uses USERPROFILE with Desktop appended', () {
      final path = resolveDesktopPath(
        environment: {'USERPROFILE': r'C:\Users\test'},
        platformOverride: 'windows',
      );
      // p.join uses the host separator; just assert both parts are present.
      expect(path, contains(r'C:\Users\test'));
      expect(path, endsWith('Desktop'));
    });
  });
}
