import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/voice_action_service.dart';

void main() {
  group('parseVoiceAction', () {
    // ── Null / empty ──────────────────────────────────────────────────────
    test('returns null for empty string', () {
      expect(parseVoiceAction(''), isNull);
    });

    test('returns null for whitespace-only string', () {
      expect(parseVoiceAction('   '), isNull);
    });

    // ── Note (default) ────────────────────────────────────────────────────
    test('returns note for plain text', () {
      final result = parseVoiceAction('Remember to fix the bug');
      expect(result, isNotNull);
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'Remember to fix the bug');
    });

    test('trims whitespace for note', () {
      final result = parseVoiceAction('  some note text  ');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'some note text');
    });

    // ── Tag detection ─────────────────────────────────────────────────────
    test('detects "tag as X" prefix', () {
      final result = parseVoiceAction('tag as important');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'important');
    });

    test('detects "Tag As X" case-insensitive', () {
      final result = parseVoiceAction('Tag As Urgent');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'Urgent');
    });

    test('detects "TAG AS X" all caps', () {
      final result = parseVoiceAction('TAG AS meeting');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'meeting');
    });

    test('detects "tag:" prefix', () {
      final result = parseVoiceAction('tag:work');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'work');
    });

    test('detects "tag: " with space after colon', () {
      final result = parseVoiceAction('tag: personal');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'personal');
    });

    test('falls back to note when tag prefix has empty payload', () {
      final result = parseVoiceAction('tag as ');
      // "tag as " with trailing space → tag name is empty after trim → note
      expect(result!.type, VoiceActionType.note);
    });

    test('falls back to note when tag: has empty payload', () {
      final result = parseVoiceAction('tag:');
      expect(result!.type, VoiceActionType.note);
    });

    // ── Correction detection ──────────────────────────────────────────────
    test('detects "correct:" prefix', () {
      final result = parseVoiceAction('correct: This is the fixed text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'This is the fixed text');
    });

    test('detects "Correct:" case-insensitive', () {
      final result = parseVoiceAction('Correct: Updated transcript');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Updated transcript');
    });

    test('detects "korrektur:" German prefix', () {
      final result = parseVoiceAction('korrektur: Das ist der korrigierte Text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Das ist der korrigierte Text');
    });

    test('detects "Korrektur:" case-insensitive', () {
      final result = parseVoiceAction('Korrektur: Neuer Inhalt');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Neuer Inhalt');
    });

    test('falls back to note when correct: has empty payload', () {
      final result = parseVoiceAction('correct:');
      expect(result!.type, VoiceActionType.note);
    });

    test('falls back to note when korrektur: has empty payload', () {
      final result = parseVoiceAction('korrektur:  ');
      expect(result!.type, VoiceActionType.note);
    });

    // ── Priority: tag > correction > note ─────────────────────────────────
    test('tag prefix takes priority over other text', () {
      final result = parseVoiceAction('tag as correct: something');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'correct: something');
    });

    // ── Equality ──────────────────────────────────────────────────────────
    test('VoiceActionResult equality', () {
      const a = VoiceActionResult(type: VoiceActionType.note, payload: 'hi');
      const b = VoiceActionResult(type: VoiceActionType.note, payload: 'hi');
      const c = VoiceActionResult(type: VoiceActionType.tag, payload: 'hi');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('VoiceActionResult toString', () {
      const r = VoiceActionResult(type: VoiceActionType.tag, payload: 'work');
      expect(r.toString(), 'VoiceActionResult(VoiceActionType.tag, "work")');
    });
  });
}
