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


def sources(root):
    for top in ('tests', 'std', 'contrib'):
        for dirpath, _, names in os.walk(os.path.join(root, top)):
            for n in sorted(names):
                if n.endswith('.ae'):
                    yield os.path.join(dirpath, n)


def main():
    offenders = []
    for path in sources(ROOT):
        with open(path, encoding='utf-8', errors='replace') as f:
            for n in check_source(f.read()):
                offenders.append('%s:%d' % (os.path.relpath(path, ROOT), n))
    if offenders:
        print('  [FAIL] platform from the environment: these read getenv("OS");'
              ' ask os.platform(), which answers from the build (#3119)')
        for o in offenders:
            print('    ' + o)
        return 1
    print('  [PASS] platform from the build: no program reads getenv("OS")')
    return 0


if __name__ == '__main__':
    sys.exit(main())
