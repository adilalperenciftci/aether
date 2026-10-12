#!/usr/bin/env python3
"""Shell tests end what they started through tests/lib/server_jobs.sh (#2479).

On Windows, a signal sent to the MSYS2 stand-in of a native program (what
`$!` names after `prog &` runs an Aether binary, `ae` or a MinGW tool) makes
the MSYS2 runtime gather the program's "descendants" by their recorded
Windows parent pid, which Windows recycles, and signal every MSYS2
process-group leader among them: on the CI runner that reached the step's
own bash, and the Windows job died with exit code 2304 and no test named.
Elsewhere a remembered pid can belong to another process once its own has
been reaped. tests/lib/server_jobs.sh ends a background program safely on
every platform (kill_server, stop_server, signal_server).

This gate reads every `*.sh` under tests/ except that helper file and fails
on, in code with comments and quoted text set aside:

  * `kill` given a pid in a variable or a substitution: `kill "$SRV_PID"`,
    `kill -9 $!`, `kill $(cat pidfile)`, `kill -- -$PGID`, `for p in $PIDS;
    do kill $p`, and `xargs kill`;
  * `pkill` and `killall`, which pick processes by name (on Windows that
    includes the stand-ins).

Allowed: signal 0 (`kill -0 "$pid"` sends nothing; it asks whether the pid
is there), a job (`kill %1`), the script's own shell (`kill -TERM $$`), and
a line marked `kill-ok: <why>`, on the line or on a comment line right
above it, for a test whose subject is a signal to a process that is not a
job of the script (POSIX-only).

Run from the repository root; exit 1 listing every offender.
"""
import os
import re
import shlex
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HELPER = os.path.join("tests", "lib", "server_jobs.sh")
WAIVER = "kill-ok:"

# A word that starts a command: line start, or after ; & | ( { ! or a
# reserved word that takes a command after it.
CMD_START = r'(?:^|[;&|(){}!`]|\b(?:then|do|else|elif|if|while|until|time|command|builtin|exec)\b)\s*'
KILL = re.compile(CMD_START + r'(kill)(?=\s|$)')
BY_NAME = re.compile(CMD_START + r'(pkill|killall)(?=\s|$)')
XARGS_KILL = re.compile(r'\bxargs\b(?:\s+-\S+)*\s+kill(?=\s|$)')
TRAP = re.compile(CMD_START + r'trap\s+')
HEREDOC = re.compile(r'<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\1')
# What ends the kill command's words.
END = re.compile(r'[;&|)}]|\s#')
REDIRECT = re.compile(r'^\d*[<>]')


def mask(line):
    """`line` with quoted text and a trailing comment replaced by blanks, so
    a `kill` inside `echo "...(kill $!)..."` or `# ...` is not a command.
    Positions are kept, so a match indexes the original line."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == '\\' and quote == '"' and i + 1 < len(line):
                out.append('  ')
                i += 2
                continue
            if c == quote:
                quote = None
                out.append(c)
            else:
                out.append(' ')
        elif c == '\\' and i + 1 < len(line):
            out.append(c + line[i + 1])
            i += 2
            continue
        elif c in ('"', "'"):
            quote = c
            out.append(c)
        elif c == '#' and (i == 0 or line[i - 1].isspace()):
            out.append(' ' * (len(line) - i))
            break
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def kill_words(line, masked, start):
    """The words of the kill command that begins at `start` (after `kill`),
    up to the end of that command."""
    m = END.search(masked, start)
    tail = line[start:m.start() if m else len(line)]
    try:
        return shlex.split(tail, posix=False)
    except ValueError:
        return tail.split()


def offending_operands(words):
    """The operands of one `kill` that name a remembered pid, or [] when the
    call is allowed (signal 0, a job, $$, a listing)."""
    signal = None
    operands = []
    i = 0
    options_done = False
    while i < len(words):
        w = words[i]
        if REDIRECT.match(w):
            if w in ('>', '<', '2>', '>>', '2>>', '&>') and i + 1 < len(words):
                i += 1
            i += 1
            continue
        if not options_done and w == '--':
            options_done = True
        elif not options_done and w in ('-l', '-L'):
            return []
        elif not options_done and signal is None and w in ('-s', '-n') and i + 1 < len(words):
            signal = words[i + 1].strip('\'"')
            i += 1
        elif (not options_done and signal is None and w.startswith('-') and len(w) > 1
              and w[1] != '$'):
            signal = w[1:]                # one signal only: a later -N is a pid
        else:
            operands.append(w)
        i += 1
    if signal is not None and signal.upper() in ('0', 'SIG0'):
        return []
    bad = []
    for op in operands:
        bare = op.strip('\'"')
        if bare.startswith('%'):
            continue                      # a job: bash resolves it safely
        if bare in ('$$', '${$}'):
            continue                      # the script's own shell
        if '$' in bare or '`' in bare or re.fullmatch(r'-?\d+', bare):
            bad.append(op)
    return bad


def heredoc(raw):
    """The match for a here-document this line starts outside quotes."""
    m = re.search(r'<<', mask(raw))
    return HEREDOC.match(raw, m.start()) if m else None


def line_offences(raw):
    """Messages for the kills on one line of shell code."""
    found = []
    masked = mask(raw)
    for m in KILL.finditer(masked):
        bad = offending_operands(kill_words(raw, masked, m.end(1)))
        if bad:
            found.append("kill of a remembered pid (%s): end it through "
                         "tests/lib/server_jobs.sh (kill_server / stop_server / "
                         "signal_server)" % " ".join(bad))
    for m in BY_NAME.finditer(masked):
        found.append("%s picks processes by name: end what the test started "
                     "through tests/lib/server_jobs.sh" % m.group(1))
    if XARGS_KILL.search(masked):
        found.append("xargs kill signals pids read from a pipe: end what the test "
                     "started through tests/lib/server_jobs.sh")
    # The command text a trap runs is quoted, but it is code all the same.
    for m in TRAP.finditer(masked):
        body = raw[m.end():]
        q = body[:1]
        if q in ('"', "'") and q in body[1:]:
            found.extend(line_offences(body[1:body.index(q, 1)]))
    return found


def check_source(src):
    """Offences in one shell source as (lineno, message)."""
    found = []
    heredoc_end = None
    above = False
    for n, raw in enumerate(src.split('\n'), 1):
        stripped = raw.strip()
        if heredoc_end is not None:
            if stripped == heredoc_end:
                heredoc_end = None
            continue
        waived = WAIVER in raw or above
        above = WAIVER in raw and stripped.startswith('#')
        h = heredoc(raw)
        if not waived:
            found.extend((n, msg) for msg in line_offences(raw))
        if h:
            heredoc_end = h.group(2)
    return found


def shell_sources(root):
    out = []
    for dirpath, _, names in os.walk(os.path.join(root, "tests")):
        for name in names:
            if name.endswith(".sh"):
                path = os.path.join(dirpath, name)
                if os.path.relpath(path, root) != HELPER:
                    out.append(path)
    return sorted(out)


def main():
    offences = []
    for path in shell_sources(ROOT):
        with open(path, encoding="utf-8", errors="replace") as f:
            src = f.read()
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for n, msg in check_source(src):
            offences.append("%s:%d: %s" % (rel, n, msg))
    if offences:
        print("shell kills: %d signal(s) sent past tests/lib/server_jobs.sh (#2479):"
              % len(offences))
        for o in offences:
            print("  " + o)
        print("  on Windows a signal to the MSYS2 stand-in of a native program also reaches")
        print("  unrelated processes, the CI step's own shell among them; mark a POSIX-only")
        print("  signal test's own kill `kill-ok: <why>`.")
        return 1
    print("shell kills: every background program the shell tests end goes through server_jobs.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
