import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/text/markdown_checklist.dart';

void main() {
  group('Markdown checklists (#643)', () {
    test('finds task lines, skipping code fences', () {
      const src =
          '- [ ] open\n'
          '  * [x] done sub\n'
          '1. [X] numbered\n'
          '- [] no box\n'
          '```\n'
          '- [ ] inside code\n'
          '```\n'
          'text [ ] not a task';
      expect(checklistItems(src), const [
        ChecklistItem(line: 0, checked: false),
        ChecklistItem(line: 1, checked: true),
        ChecklistItem(line: 2, checked: true),
      ]);
      expect(isChecklistLineChecked('- [x] a'), isTrue);
      expect(isChecklistLineChecked('- [ ] a'), isFalse);
      expect(isChecklistLineChecked('- a'), isNull);
    });

    test('toggling rewrites only the box and keeps CRLF', () {
      const src = '# List\r\n- [ ] milk\r\n- [x] bread\r\n';
      final once = toggleChecklistItem(src, 1);
      expect(once, '# List\r\n- [x] milk\r\n- [x] bread\r\n');
      expect(
        toggleChecklistItem(once, 2),
        '# List\r\n- [x] milk\r\n- [ ] bread\r\n',
      );
      expect(toggleChecklistItem(src, 0), src);
      expect(toggleChecklistItem(src, 99), src);
      expect(toggleChecklistItem('```\n- [ ] x\n```', 1), '```\n- [ ] x\n```');
    });

    test('check all and reset touch every box and nothing else', () {
      const src = 'Shop:\n- [ ] a\n- [X] b\n  - [ ] c\n- plain';
      expect(
        setAllChecklistItems(src, checked: true),
        'Shop:\n- [x] a\n- [X] b\n  - [x] c\n- plain',
      );
      expect(
        setAllChecklistItems(src, checked: false),
        'Shop:\n- [ ] a\n- [ ] b\n  - [ ] c\n- plain',
      );
      expect(setAllChecklistItems('no tasks', checked: true), 'no tasks');
    });

    test('moving done items down keeps order and carries sub-lines', () {
      const src =
          'Today\n'
          '- [x] first done\n'
          '  - [ ] its sub\n'
          '- [ ] open one\n'
          '- [x] second done\n'
          '- [ ] open two\n'
          '\n'
          '- [x] other list done\n'
          '- [ ] other list open';
      expect(
        moveCheckedToBottom(src),
        'Today\n'
        '- [ ] open one\n'
        '- [ ] open two\n'
        '- [x] first done\n'
        '  - [ ] its sub\n'
        '- [x] second done\n'
        '\n'
        '- [ ] other list open\n'
        '- [x] other list done',
      );
    });

    test('a list mixing tasks and plain bullets stays as written', () {
      const src = '- [x] done\n- plain bullet\n- [ ] open';
      expect(moveCheckedToBottom(src), src);
      const fenced = '```\n- [x] a\n- [ ] b\n```\n- [ ] c';
      expect(moveCheckedToBottom(fenced), fenced);
    });
  });
}
