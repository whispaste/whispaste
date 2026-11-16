#!/usr/bin/env python3
"""tests-checked: gate for changed test files (#1415), run by scripts/ci-gates.sh (gate `tests`).

Changed test files are checked statically for slow, flaky or silent patterns:
real waiting, clock or network dependence, console output, a new unconditional
skip, or a test without an assertion. Runtime acceptance belongs to lab/ubu and
lab/win after the dev merge; a commit-message proof is not a runtime CI status.

`// test-ok: <reason>` on the line waives the three heuristic rules (wait, clock, network); nothing waives
sleep, console output, skips and missing assertions.
BASE_SHA unset or all zeros (first push of a branch, manual run): nothing to compare, the gate passes.
"""
import os
import re
import subprocess
import sys

TESTS = ':(glob)test/**/*_test.dart'
WAIVER = re.compile(r'//\s*test-ok:\s*\S.{9,}')
FAKE_TIME = re.compile(r'\b(fakeAsync|FakeAsync|testWidgets)\b')
TEST_START = re.compile(r'^(\s*)(test|testWidgets|blocTest)\s*(<[^>]*>)?\(')
# a test named by a variable (`testWidgets(description, ...)`) is a wrapper inside a test helper
WRAPPER_NAME = re.compile(r'\s*[A-Za-z_]\w*\s*,')
ASSERTS = re.compile(r'expect|verif|assert|check|fail\(|throws', re.I)
# single-line string literals (test names, reasons, messages) are removed before ASSERTS looks at a body
STRING = re.compile(r"'(?:[^'\\\n]|\\.)*'" + r'|"(?:[^"\\\n]|\\.)*"')
# (reason, pattern, waivable)
RULES = [
    ('real waiting: sleep() blocks the run', re.compile(r'(?<![\w.])sleep\('), False),
    ('console output in a test', re.compile(r'(?<![\w.])print\(|debugPrint\(|\bstd(out|err)\.write(ln)?\('), False),
    ('new unconditional skip', re.compile(r'''\bskip:\s*(true\b|['"])|@Skip\(|markTestSkipped\('''), False),
    ('clock dependence: inject the time (package:clock, withClock) instead of DateTime.now()',
     re.compile(r'\bDateTime\.(now|timestamp)\('), True),
    ('network dependence: use a fake client or transport',
     re.compile(r'\bHttpClient\(\)|\bInternetAddress\.lookup\(|\b(Raw)?Socket\.connect\('), True),
]
DELAYED = re.compile(r'\bFuture(<[^>]*>)?\.delayed\((?!\s*Duration\.zero)')


def git(*args):
    return subprocess.run(('git',) + args, capture_output=True, text=True, check=True).stdout


def changed(old, new):
    return [f for f in git('diff', '-z', '--name-only', '--diff-filter=AM', '--no-renames', old, new, '--',
                           TESTS).split('\0') if f]


def added_lines(old, new, files):
    """{file: {line number: text}} of the lines added in old..new."""
    added, path, number = {}, None, 0
    for line in git('diff', '-U0', '--no-renames', old, new, '--', *files).splitlines():
        hunk = re.match(r'@@ -\S+ \+(\d+)', line)
        if line.startswith('+++ '):
            path = line[6:] if line.startswith('+++ b/') else None
        elif hunk:
            number = int(hunk.group(1))
        elif line.startswith('+') and path:
            added.setdefault(path, {})[number] = line[1:]
            number += 1
    return added


def string_lines(lines):
    """1-based numbers of the lines after the opening of a multi-line string literal up to its closing line:
    fixture source inside ''' or \"\"\" is data, not test code."""
    inside, quote, found = False, '', set()
    for number, line in enumerate(lines, 1):
        if inside:
            found.add(number)
        rest = line
        while True:
            if inside:
                end = rest.find(quote)
                if end < 0:
                    break
                inside, rest = False, rest[end + 3:]
            else:
                start = re.search(r"'''|\"\"\"", rest)
                if not start:
                    break
                inside, quote, rest = True, start.group(), rest[start.end():]
    return found


def without_assertion(lines, added):
    """Line numbers of added tests whose body holds no assertion (body: the start line and all deeper lines,
    across a wrapped `) async {` and multi-line string literals)."""
    found, strings = [], string_lines(lines)
    for index, line in enumerate(lines):
        start = TEST_START.match(line)
        if not start or index + 1 not in added or index + 1 in strings:
            continue
        if WRAPPER_NAME.match(line, start.end()):
            continue  # helper that forwards a body: the assertions sit at its call sites
        body, depth = [line], len(start.group(1))
        for offset, follow in enumerate(lines[index + 1:], index + 2):
            indent = len(follow) - len(follow.lstrip())
            if follow.strip() and indent <= depth and offset not in strings:
                if follow.lstrip().startswith(')') and follow.rstrip().endswith('{'):
                    body.append(follow)  # `) async {` of a parameter list wrapped by dart format
                    continue
                body.append(follow if follow.lstrip()[:1] in '})' else '')
                break
            body.append('' if offset in strings else follow)
        if not ASSERTS.search(STRING.sub("''", '\n'.join(body))):
            found.append(index + 1)
    return found


def static_findings(old, new):
    findings, files = [], changed(old, new)
    for path, added in sorted(added_lines(old, new, files).items() if files else []):
        text = git('show', '%s:%s' % (new, path))
        fake_time, strings = FAKE_TIME.search(text), string_lines(text.splitlines())
        for number, line in sorted(added.items()):
            if line.lstrip().startswith('//') or number in strings:
                continue
            rules = list(RULES)
            if not fake_time:
                rules.append(('real waiting: Future.delayed outside fakeAsync; use fakeAsync and elapse()', DELAYED, True))
            for reason, pattern, waivable in rules:
                if pattern.search(line) and not (waivable and WAIVER.search(line)):
                    findings.append('%s:%d: %s' % (path, number, reason))
        findings += ['%s:%d: test without an assertion' % (path, n) for n in without_assertion(text.splitlines(), added)]
    return findings


def main():
    base = os.environ.get('BASE_SHA', '')
    if not base.strip('0'):
        print('tests-checked: no base commit, nothing to compare')
        return 0
    try:
        fork = git('merge-base', base, 'HEAD').strip()
    except subprocess.CalledProcessError:
        print('tests-checked: RED: base %s is not in this clone, changed test files cannot be checked' % base[:10])
        return 1
    files = changed(fork, 'HEAD')
    if not files:
        print('tests-checked: no changed test files')
        return 0
    problems = static_findings(fork, 'HEAD')
    for problem in problems:
        print('tests-checked: RED: ' + problem)
    if not problems:
        print('tests-checked: %d changed test file(s) statically clean; runtime validation runs in lab CI' % len(files))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
