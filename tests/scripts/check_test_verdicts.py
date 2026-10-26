#!/usr/bin/env python3
"""A sweep-run .ae test that prints a failure must be able to fail (#2132).

The bulk `.ae` sweep has one oracle: the process exit code. A test that
prints `FAIL ...` on a bad result and then returns from a void `main()` —
or falls through to its end — exits 0 and is counted as a pass on every
run. Twenty-five tests were found in that state, two of them the OCSP and
ECDSA-P384 certificate checks.

This gate flags any `.ae` the sweep runs that, with comments stripped,
prints a `FAIL` / `FAILURE` / `MISMATCH` / `WRONG` marker and has none of
the ways a verdict reaches the exit code:

  * `exit(` — the C exit, bypasses main's scope-end cleanup;
  * `return <non-zero>` inside `main()` — the exit code with cleanup;
  * `panic(`;
  * `std.testing` / `std.spec` — the frameworks carry the verdict;

and has no `test_*.sh` driver in its directory (a driver greps the output
or checks the exit code itself).

std.spec carries the verdict only through `run_summary`'s value, which
main has to return (or pass to `exit`): `run_summary` returns it and does
not exit. A suite that calls it as a bare statement drops the verdict and
exits 0 with failing cases (#2678). So every `.ae` test, the sweep's and
contrib's, is also checked for a bare `run_summary(...)` statement.

Run from the repository root; exit 1 listing every offender.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MARKER = re.compile(r'println\(\s*"[^"]*\b(FAIL|FAILURE|MISMATCH|WRONG)\b')
VERDICT = re.compile(
    r'\bexit\(|\bpanic\(|\bimport\s+std\.testing\b|\bimport\s+std\.spec\b')
MAIN_RETURN = re.compile(r'\breturn\s+[1-9]')
# `spec.run_summary(fw)` (or a bare `run_summary(fw)` from a selective
# import) as a whole statement: its verdict goes nowhere.
DROPPED_SUMMARY = re.compile(r'^\s*(?:spec\.)?run_summary\([^()]*\)\s*$', re.M)
# The verdict bound to a name, `_rc = spec.run_summary(fw)`: dropped too when
# nothing reads the name again. std.sandbox's two suites exited 0 that way
# with five failing cases on Windows.
BOUND_SUMMARY = re.compile(r'^\s*([A-Za-z_]\w*)\s*=\s*(?:spec\.)?run_summary\([^()]*\)\s*$', re.M)


def drops_verdict(src):
    """Does `src` (comments stripped) drop run_summary's verdict: call it as
    a bare statement, or bind it to a name nothing reads?"""
    if DROPPED_SUMMARY.search(src):
        return True
    for m in BOUND_SUMMARY.finditer(src):
        name = re.escape(m.group(1))
        if len(re.findall(r'(?<![\w.])' + name + r'(?!\w)', src)) < 2:
            return True
    return False


def prune_patterns():
    out = []
    with open(os.path.join(ROOT, 'tests', 'ae_sweep_prune.txt'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                out.append(line)
    return out


def swept_files():
    prunes = prune_patterns()
    roots = [os.path.join(ROOT, 'tests', d) for d in ('syntax', 'compiler', 'integration', 'regression')]
    files = []
    for r in roots:
        for dirpath, _, names in os.walk(r):
            for n in names:
                if n.endswith('.ae'):
                    files.append(os.path.join(dirpath, n))
    std = os.path.join(ROOT, 'std')
    for dirpath, _, names in os.walk(std):
        for n in names:
            if n.startswith('test_') and n.endswith('.ae'):
                files.append(os.path.join(dirpath, n))
    kept = []
    for p in files:
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if any(pat in rel for pat in prunes):
            continue
        kept.append(p)
    return kept


def contrib_tests():
    """contrib's test_*.ae: not in the bulk sweep, run by contrib-check,
    whose oracle is the exit code too."""
    out = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, 'contrib')):
        for n in names:
            if n.startswith('test_') and n.endswith('.ae'):
                out.append(os.path.join(dirpath, n))
    return out


def strip_comments(src):
    """Drop `// ...` to end of line, leaving string literals alone (a
    `//` inside a string is not a comment)."""
    out = []
    for line in src.split('\n'):
        in_str = False
        i = 0
        while i < len(line):
            c = line[i]
            if c == '"' and (i == 0 or line[i - 1] != '\\'):
                in_str = not in_str
            elif not in_str and line.startswith('//', i):
                line = line[:i]
                break
            i += 1
        out.append(line)
    return '\n'.join(out)


def main_body(src):
    """The text of `main() { ... }`, by brace depth; '' when there is none."""
    m = re.search(r'^main\(\)\s*\{', src, re.M)
    if not m:
        return ''
    depth = 0
    for i in range(m.end() - 1, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[m.end():i]
    return src[m.end():]


def has_driver(path):
    d = os.path.dirname(path)
    return any(n.startswith('test_') and n.endswith('.sh') for n in os.listdir(d))


def main():
    offenders = []
    dropped = []
    swept = swept_files()
    for p in swept + contrib_tests():
        with open(p, encoding='utf-8', errors='replace') as f:
            src = strip_comments(f.read())
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if drops_verdict(src):
            dropped.append(rel)
        if p not in swept or not MARKER.search(src):
            continue
        if VERDICT.search(src) or MAIN_RETURN.search(main_body(src)):
            continue
        if has_driver(p):
            continue
        offenders.append(rel)
    status = 0
    if offenders:
        print("test verdicts: %d sweep-run test(s) print a failure marker but cannot exit non-zero:" % len(offenders))
        for o in sorted(offenders):
            print("  " + o)
        print("  make the failure branch reach the exit code: `return 1` from main(), or exit(1).")
        status = 1
    if dropped:
        print("test verdicts: %d test(s) call run_summary and drop its verdict, so a failing suite exits 0:" % len(dropped))
        for o in sorted(dropped):
            print("  " + o)
        print("  return it from main(): `return spec.run_summary(fw)`.")
        status = 1
    if status == 0:
        print("test verdicts: every sweep-run test that prints a failure marker can exit non-zero,"
              " and every std.spec suite returns its verdict")
    return status


if __name__ == '__main__':
    sys.exit(main())
