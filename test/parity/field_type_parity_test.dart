// Contract guard for the field-type channel (#948): Dart and the Windows
// runner agree on channel and method, the native side reads only role and
// attributes (never field content), and the check runs before any paste.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  const host = 'windows/runner/field_type_host.cpp';
  const reader = 'windows/runner/field_type_reader.cpp';
  const controller =
      'lib/services/desktop_paste/windows_desktop_paste_controller.dart';
  const paster = 'lib/services/paste/desktop_paster.dart';

  test('Windows host and Dart controller share channel and method', () {
    final hostSource = _read(host);
    final dartSource = _read(controller);
    expect(hostSource, contains('"com.whispaste.field_type"'));
    expect(hostSource, contains('"focusedFieldType"'));
    expect(dartSource, contains("'com.whispaste.field_type'"));
    expect(
      dartSource,
      matches(RegExp(r"invokeMethod<String>\(\s*'focusedFieldType'")),
    );
  });

  test('macOS host and Dart controller share channel and method', () {
    final hostSource = _read('macos/Runner/FieldTypeHost.swift');
    final dartSource = _read(
      'lib/services/desktop_paste/macos_desktop_paste_controller.dart',
    );
    expect(hostSource, contains('name: "com.whispaste.field_type"'));
    expect(hostSource, contains('"focusedFieldType"'));
    expect(
      dartSource,
      matches(RegExp(r"invokeMethod<String>\(\s*'focusedFieldType'")),
    );
    expect(dartSource, contains('fieldTypeChannelName'));
    expect(dartSource, contains('implements FocusedFieldTypeProbe'));
  });

  test('macOS reads only role and subrole and never prompts', () {
    final source = _read('macos/Runner/FieldTypeHost.swift');
    for (final code in ['"password"', '"normal"', '"unknown"']) {
      expect(source, contains(code));
    }
    expect(source, contains('kAXSecureTextFieldSubrole'));
    expect(source, contains('AXIsProcessTrusted()'));
    expect(source, isNot(contains('AXIsProcessTrustedWithOptions')));
    for (final contentRead in [
      'kAXValueAttribute',
      'kAXSelectedTextAttribute',
      'kAXTitleAttribute',
      'kAXDescriptionAttribute',
      'kAXStringForRange',
      'kAXPlaceholderValueAttribute',
    ]) {
      expect(source, isNot(contains(contentRead)), reason: contentRead);
    }
  });

  test('Linux host and Dart controller share channel and method (#950)', () {
    final hostSource = _read('linux/runner/target_field_host.cc');
    final dartSource = _read(
      'lib/services/desktop_paste/linux_desktop_paste_controller.dart',
    );
    expect(hostSource, contains('"com.whispaste.field_type"'));
    expect(hostSource, contains('"focusedFieldType"'));
    expect(dartSource, contains("'com.whispaste.field_type'"));
    expect(
      dartSource,
      matches(RegExp(r"invokeMethod<String>\(\s*'focusedFieldType'")),
    );
    expect(dartSource, contains('implements FocusedFieldTypeProbe'));
  });

  test('the Linux probe reads only the role, never field content (#950)', () {
    final source = _read('linux/runner/target_field_host.cc');
    final start = source.indexOf('std::string ProbeFieldType()');
    final end = source.indexOf('struct TypePending');
    expect(start, isNonNegative);
    final body = source.substring(start, end);
    for (final code in ['"password"', '"normal"', '"unknown"']) {
      expect(body, contains(code));
    }
    expect(body, contains('IsPasswordRole'));
    for (final contentRead in ['GetText', 'kText, "', 'GetSelection']) {
      expect(body, isNot(contains(contentRead)), reason: contentRead);
    }
  });

  test('the wire carries only the type codes', () {
    final readerSource = _read(reader);
    for (final code in ['"password"', '"normal"', '"unknown"']) {
      expect(readerSource, contains(code));
    }
  });

  test('the reader asks for IsPassword and never reads field content', () {
    final readerSource = _read(reader);
    expect(readerSource, contains('get_CurrentIsPassword'));
    for (final contentRead in [
      'GetText',
      'get_CurrentValue',
      'get_CurrentName',
      'get_DocumentRange',
      'GetSelection',
      'GetWindowText',
      'WM_GETTEXT',
    ]) {
      expect(readerSource, isNot(contains(contentRead)), reason: contentRead);
    }
  });

  test('the field-type check runs before the paste shortcut', () {
    final source = _read(paster);
    final start = source.indexOf('Future<PasteOutcome> _pasteUnlocked(');
    expect(start, isNonNegative);
    final check = source.indexOf('_checkFieldType(text)', start);
    final saved = source.indexOf('_saveClipboard()', start);
    expect(check, isNonNegative);
    expect(check, lessThan(saved));

    final typeStart = source.indexOf('Future<PasteOutcome> _typeTextUnlocked(');
    final typeCheck = source.indexOf('_checkFieldType(text)', typeStart);
    final typeCall = source.indexOf('_controller.typeText(', typeStart);
    expect(typeCheck, isNonNegative);
    expect(typeCheck, lessThan(typeCall));
  });
}
