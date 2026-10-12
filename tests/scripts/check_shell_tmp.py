#!/usr/bin/env python3
"""Shell tests do not write fixed paths under /tmp (#2770).

Two test sweeps on one machine (two checkouts, or the parallel agents that
work this repository) run the same tests at the same time. A test that
writes /tmp/ae_bfc_bad.ae has the other sweep's copy overwrite or delete it
mid-test, and it fails at random; it also leaves the file behind. A test
makes a directory of its own instead (`mktemp -d`, removed by an EXIT trap)
and writes there.

This gate reads every `*.sh` under tests/ except the CI tooling under
tests/scripts/, the nightly drivers and the ESP32 driver (which runs inside
a container of its own), and fails on a `/tmp/<name>` outside a comment or
a heredoc body (the body is data, mostly a program the test compiles),
unless the line also builds the name from `mktemp` or `TMPDIR`
(`"${TMPDIR:-/tmp}/ae_x_$$"` is unique per process) or carries a
`tmp-ok: <why>` note on the line or on a comment line right above it.

Run from the repository root; exit 1 listing every offender.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKIP_DIRS = (
    os.path.join("tests", "scripts") + os.sep,
    os.path.join("tests", "cachyos") + os.sep,
    os.path.join("tests", "freebsd") + os.sep,
    os.path.join("tests", "esp32") + os.sep,
)
WAIVER = "tmp-ok:"
FIXED_TMP = re.compile(r"(?<![\w$}/.-])/tmp/[A-Za-z0-9_]")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")


def strip_comment(line):
    """The line without a trailing `# ...` comment, outside quotes."""
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t;"):
            break
        out.append(ch)
    return "".join(out)


def offenders_in(text):
    """(line number, line) of each fixed /tmp path in a script's text."""
    found = []
    lines = text.split("\n")
    doc_end = None
    for i, line in enumerate(lines):
        if doc_end is not None:
            if line.strip() == doc_end:
                doc_end = None
            continue
        if line.lstrip().startswith("#"):
            continue
        code = strip_comment(line)
        m = HEREDOC.search(code)
        if m:
            doc_end = m.group(2)
        if not FIXED_TMP.search(code):
            continue
        if "mktemp" in code or "TMPDIR" in code:
            continue
        above = lines[i - 1] if i > 0 else ""
        if WAIVER in line or (above.lstrip().startswith("#") and WAIVER in above):
            continue
        found.append((i + 1, line.strip()))
    return found


def main():
    bad = []
    tests_dir = os.path.join(ROOT, "tests")
    for dirpath, _dirs, files in os.walk(tests_dir):
        rel_dir = os.path.relpath(dirpath, ROOT) + os.sep
        if rel_dir.startswith(SKIP_DIRS):
            continue
        for name in sorted(files):
            if not name.endswith(".sh"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="replace") as f:
                for lineno, line in offenders_in(f.read()):
                    bad.append("%s:%d: %s" % (os.path.relpath(path, ROOT), lineno, line))
    if bad:
        print("shell tests write fixed /tmp paths; use a mktemp -d directory (#2770):")
        for b in bad:
            print("  " + b)
        return 1
    print("shell tmp: no shell test writes a fixed /tmp path")
    return 0


if __name__ == "__main__":
    sys.exit(main())
