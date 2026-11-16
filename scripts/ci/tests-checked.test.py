#!/usr/bin/env python3
"""#1415 offline: scripts/ci/tests-checked.py against throwaway repos. Run: python3 -I scripts/ci/tests-checked.test.py"""
import os
import shutil
import subprocess
import sys
import tempfile

GATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tests-checked.py')
TMP = tempfile.mkdtemp(prefix='tests-checked-')
GOOD = "test('adds', () {\n  expect(1 + 1, 2);\n});\n"


def sh(path, script):
    return subprocess.run(['sh', '-ec', script], cwd=path, check=True, capture_output=True, text=True).stdout.strip()


def repo(gated=True):
    path = tempfile.mkdtemp(dir=TMP)
    sh(path, 'git init -q -b dev . && git config user.email t && git config user.name t && '
             'mkdir -p test/a lib scripts/ci && echo "void main() {}" > test/a/old_test.dart && %s'
             'git add . && git commit -qm base' % ('touch scripts/ci/tests-checked.py && ' if gated else ''))
    return path, sh(path, 'git rev-parse HEAD')


def write(path, name, text, message='tests'):
    with open(os.path.join(path, name), 'w') as fh:
        fh.write(text)
    sh(path, 'git add . && git commit -qm "%s"' % message)


def gate(path, base):
    done = subprocess.run([sys.executable, '-I', GATE], cwd=path, capture_output=True, text=True,
                          env=dict(os.environ, BASE_SHA=base))
    return done.returncode, done.stdout


def static(line, name='test/a/x_test.dart', head=''):
    path, base = repo()
    write(path, name, head + "test('t', () {\n  %s\n  expect(1, 1);\n});\n" % line)
    return gate(path, base)


def main():
    checks = {}
    path, base = repo()
    write(path, 'lib/code.dart', 'int a = 1;\n')
    checks['no test file changed'] = gate(path, base)[0] == 0
    checks['no base, nothing to compare'] = gate(path, '0' * 40)[0] == 0 and gate(path, '')[0] == 0
    checks['unknown base is red'] = gate(path, 'f' * 40)[0] == 1

    write(path, 'test/a/new_test.dart', GOOD)
    code, out = gate(path, base)
    checks['clean tests need no pre-merge runtime proof'] = code == 0 and 'statically clean' in out
    write(path, 'test/a/new_test.dart', GOOD + GOOD)
    checks['later clean edits remain static-only'] = gate(path, base)[0] == 0
    write(path, 'test/a/new_test.dart', GOOD + "test('bad', () { print('x'); });\n")
    checks['later unsafe edits still fail'] = gate(path, base)[0] == 1

    red = {'sleep(const Duration(seconds: 1));': 'sleep()',
           'sleep(d); // test-ok: needed for the handoff': 'sleep()',
           "print('x');": 'console output', 'debugPrint(x);': 'console output',
           'final now = DateTime.now();': 'clock dependence',
           'final c = HttpClient();': 'network dependence',
           'await Future.delayed(const Duration(seconds: 1));': 'Future.delayed outside fakeAsync',
           "}, skip: 'later'); test('u', () {": 'unconditional skip',
           '}, skip: true); test("u", () {': 'unconditional skip'}
    for line, reason in red.items():
        code, out = static(line)
        checks['red: ' + line[:38]] = code == 1 and reason in out and 'x_test.dart:2:' in out
    green = ['final now = DateTime.now(); // test-ok: only compared with itself',
             'await Future.delayed(Duration.zero);', '// print(1) in a comment', 'blueprint(x); stdoutSink.close();',
             "}, skip: Platform.isWindows ? 'posix only' : false); test('u', () {"]
    for line in green:
        checks['green: ' + line[:36]] = static(line)[0] == 0
    checks['green: delayed under fakeAsync'] = static('await Future.delayed(const Duration(seconds: 1));',
                                                      head='// uses fakeAsync((async) {})\n')[0] == 0

    path, base = repo()
    write(path, 'test/a/y_test.dart', "test('nothing', () {\n  final a = 1;\n});\n" + GOOD
          + "test('one line', () => expect(1, 1));\ntestWidgets('helper', (t) async {\n  await pumpAndVerify(t);\n});\n"
          + "testWidgets('wrapped by dart format', (\n  tester,\n) async {\n  expect(1, 1);\n});\n"
          + "testWidgets('wrapped, empty', (\n  tester,\n) async {\n  final a = 1;\n});\n")
    code, out = gate(path, base)
    checks['test without an assertion'] = code == 1 and out.count('without an assertion') == 2 and 'y_test.dart:1:' in out

    # words in string literals (test name, reason) are no assertion: 'is asserted' or 'checks' in a name must not
    # hide an empty body (#1412 probe: a test named "...nothing asserted" passed the gate)
    path, base = repo()
    write(path, 'test/a/n_test.dart', "test('value is asserted later', () {\n  final a = 1;\n});\n"
          + "test(\"checks nothing\", () {\n  a.toString();\n});\n"
          + "test('reason only', () {\n  expect(1, 1, reason: 'checked');\n});\n")
    code, out = gate(path, base)
    checks['names are no assertion'] = (code == 1 and out.count('without an assertion') == 2
                                        and 'n_test.dart:1:' in out and 'n_test.dart:4:' in out)

    # a helper wrapping testWidgets with a variable name forwards the body: not a test of its own
    path, base = repo()
    write(path, 'test/a/w_test.dart', "void fakeTimeTest(String description, Future<void> Function() body) {\n"
          "  testWidgets(description, (tester) async {\n    await body();\n  });\n}\n"
          "void main() {\n  test('empty', () {});\n}\n")
    code, out = gate(path, base)
    checks['wrapper helpers'] = (code == 1 and out.count('without an assertion') == 1 and 'w_test.dart:7:' in out)

    # fixture source inside a multi-line string is data: no rule fires on it, it does not end the test body
    path, base = repo()
    write(path, 'test/a/s_test.dart', "test('counts skips', () {\n  const source = '''\ntest('a', () {}, skip: 'why');\n"
          "print(1);\n''';\n  expect(count(source), 1);\n});\n"
          "test('empty with fixture', () {\n  const s = \"\"\"\ntest('b', () { expect(1, 1); });\n\"\"\";\n});\n")
    code, out = gate(path, base)
    checks['multi-line string fixtures'] = (code == 1 and out.count('RED') == 1
                                            and 's_test.dart:8: test without an assertion' in out)

    # old findings in a touched file do not count: only added lines
    path, _ = repo()
    write(path, 'test/a/z_test.dart', "test('old', () {\n  print(1);\n});\n", 'old')
    base = sh(path, 'git rev-parse HEAD')
    write(path, 'test/a/z_test.dart', "test('old', () {\n  print(1);\n});\n" + GOOD)
    checks['only added lines count'] = gate(path, base)[0] == 0

    for name, ok in checks.items():
        print('%-48s %s' % (name, 'PASS' if ok else 'FAIL'))
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    finally:
        shutil.rmtree(TMP)
