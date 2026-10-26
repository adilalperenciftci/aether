#!/usr/bin/env python3
"""Programs ask the build which platform they run on, not the environment (#3119).

`getenv("OS") == "Windows_NT"` reads a variable cmd.exe and the Windows
desktop set. A shell that does not carry it (an MSYS2 login shell started
without the user's environment, a CI step or a service with a clean
environment) takes the POSIX branch of a program built for Windows, and the
test fails. `os.platform()` answers from the build.

This gate reads every .ae file under tests/, std/ and contrib/ and fails on a
`getenv("OS")` outside a comment, whichever spelling calls it (`os.getenv`,
`os_getenv`, a bare `getenv`).

It also reads every shell script under tests/, and fails on a read of `$OS`
in a script that never sets OS itself: that is the environment's variable,
and the same gap. std_ipc_bash_chain and std_ipc_roundtrip skipped on
Windows only when `[ "$OS" = "Windows_NT" ]`, so a sweep run from an MSYS2
login shell started by Git Bash, which does not pass OS on, ran their POSIX
path on Windows and failed. A script asks `uname -s` (MINGW*, MSYS*, CYGWIN*
on Windows), as the rest of the suite does. A script that keeps its own
`OS="$(uname -s)"` reads it freely.

Run from the repository root; exit 1 listing every offender.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_test_verdicts import ROOT, strip_comments  # noqa: E402

# `os_getenv` too: `_` is a word character, so `\b` would not split it off.
OS_FROM_ENV = re.compile(r'(?<![A-Za-z0-9])getenv\(\s*"OS"\s*\)')


def check_source(src):
    """The line numbers (1-based) that read `OS` from the environment."""
    return [n for n, line in enumerate(strip_comments(src).split('\n'), 1)
            if OS_FROM_ENV.search(line)]


# Shell: `$OS` or `${OS...}`, not `$OSTYPE`; and an assignment of OS.
SH_OS_READ = re.compile(r'\$\{?OS(?![A-Za-z0-9_])')
SH_OS_SET = re.compile(r'(?:^|[\s;&|(])(?:export\s+|local\s+|readonly\s+)?OS=')
SH_OS_LOOP = re.compile(r'\b(?:for|read)\b[^;#]*\bOS\b')


def strip_sh_comments(src):
    """Drop a shell comment (`#` at the start of a word, outside quotes) to
    the end of its line."""
    out = []
    for line in src.split('\n'):
        quote = None
        for i, c in enumerate(line):
            if quote:
                if c == quote and (quote == "'" or line[i - 1] != '\\'):
                    quote = None
            elif c in ('"', "'"):
                quote = c
            elif c == '#' and (i == 0 or line[i - 1].isspace()):
                line = line[:i]
                break
        out.append(line)
    return '\n'.join(out)


def check_shell_source(src):
    """The line numbers (1-based) that read the environment's OS: a `$OS` in
    a script that never sets OS itself."""
    code = strip_sh_comments(src)
    if SH_OS_SET.search(code) or SH_OS_LOOP.search(code):
        return []
    return [n for n, line in enumerate(code.split('\n'), 1) if SH_OS_READ.search(line)]


def sources(root):
    for top in ('tests', 'std', 'contrib'):
        for dirpath, _, names in os.walk(os.path.join(root, top)):
            for n in sorted(names):
                if n.endswith('.ae'):
                    yield os.path.join(dirpath, n)


def shell_sources(root):
    for dirpath, _, names in os.walk(os.path.join(root, 'tests')):
        for n in sorted(names):
            if n.endswith('.sh'):
                yield os.path.join(dirpath, n)


def main():
    offenders = []
    for path in sources(ROOT):
        with open(path, encoding='utf-8', errors='replace') as f:
            for n in check_source(f.read()):
                offenders.append('%s:%d' % (os.path.relpath(path, ROOT), n))
    sh_offenders = []
    for path in shell_sources(ROOT):
        with open(path, encoding='utf-8', errors='replace') as f:
            for n in check_shell_source(f.read()):
                sh_offenders.append('%s:%d' % (os.path.relpath(path, ROOT), n))
    if offenders:
        print('  [FAIL] platform from the environment: these read getenv("OS");'
              ' ask os.platform(), which answers from the build (#3119)')
        for o in offenders:
            print('    ' + o)
    if sh_offenders:
        print('  [FAIL] platform from the environment: these shell scripts read'
              ' $OS, which they never set; ask `uname -s` (MINGW*|MSYS*|CYGWIN*'
              ' on Windows)')
        for o in sh_offenders:
            print('    ' + o)
    if offenders or sh_offenders:
        return 1
    print('  [PASS] platform from the build: no program reads getenv("OS"),'
          ' no shell script the environment\'s $OS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
