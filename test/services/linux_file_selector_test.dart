import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/linux_file_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.whispaste.file_dialog');
  late List<Map<Object?, Object?>> calls;
  late List<String> answer;

  setUp(() {
    calls = [];
    answer = const [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'show');
          calls.add(call.arguments as Map<Object?, Object?>);
          return answer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  LinuxFileSelector selector(String language) =>
      LinuxFileSelector(lookupL10n(Locale(language)));

  test('open dialog is titled and labelled in the app language', () async {
    answer = ['/tmp/a.csv'];
    final file = await selector('de').openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
      initialDirectory: '/tmp',
    );

    expect(file?.path, '/tmp/a.csv');
    expect(calls.single, {
      'action': 'open',
      'title': 'Datei öffnen',
      'accept': 'Öffnen',
      'cancel': 'Abbrechen',
      'multiple': false,
      'filters': [
        {
          'label': 'CSV',
          'patterns': ['*.csv'],
          'mimeTypes': <String>[],
        },
      ],
      'folder': '/tmp',
      'createFolders': false,
    });
  });

  test('multi-file open returns every picked path', () async {
    answer = ['/a.wav', '/b.mp3'];
    final files = await selector('es').openFiles();

    expect([for (final f in files) f.path], ['/a.wav', '/b.mp3']);
    expect(calls.single['title'], 'Abrir archivos');
    expect(calls.single['multiple'], isTrue);
    expect(calls.single.containsKey('filters'), isFalse);
  });

  test(
    'save dialog passes the suggested name and allows new folders',
    () async {
      answer = ['/home/x/export.md'];
      final location = await selector('ru').getSaveLocation(
        options: const SaveDialogOptions(suggestedName: 'export.md'),
      );

      expect(location?.path, '/home/x/export.md');
      expect(calls.single['action'], 'save');
      expect(calls.single['title'], 'Сохранить файл');
      expect(calls.single['accept'], 'Сохранить');
      expect(calls.single['name'], 'export.md');
      expect(calls.single['createFolders'], isTrue);
    },
  );

  test('folder dialog uses its own confirm label', () async {
    answer = ['/data'];
    expect(await selector('he').getDirectoryPath(), '/data');
    expect(calls.single['action'], 'folder');
    expect(calls.single['title'], 'בחירת תיקייה');
    expect(calls.single['accept'], 'בחירה');
  });

  test('a cancelled dialog yields no selection', () async {
    final s = selector('en');
    expect(await s.openFile(), isNull);
    expect(await s.getSaveLocation(), isNull);
    expect(await s.getDirectoryPath(), isNull);
  });

  test('an explicit confirm label wins over the default', () async {
    await selector('pt').openFile(confirmButtonText: 'Importar');
    expect(calls.single['accept'], 'Importar');
  });

  test('install relabels the installed selector on a language change', () {
    final original = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = original);

    LinuxFileSelector.install(lookupL10n(const Locale('en')));
    final installed = FileSelectorPlatform.instance as LinuxFileSelector;
    LinuxFileSelector.install(lookupL10n(const Locale('de')));

    expect(FileSelectorPlatform.instance, same(installed));
    expect(installed.l10n.fileDialogSaveTitle, 'Datei speichern');
  });
}
