#!/usr/bin/env python3
"""Test programs write under the temp directory with names of their own (#2771).

Two test sweeps on one machine (two checkouts, or the parallel agents that
work this repository) run the same test programs at the same time. A test
that writes "${os.temp_dir()}/aether_fs_copy_test" has the other sweep's
copy delete or overwrite it mid-test, and it fails at random
("cannot open file for writing"); regression_test_fs_copy failed that way.
A test names what it writes with a part of its own process
(`"${tmp}/aether_fs_copy_test_${os.getpid()}"`), or writes inside a
directory made fresh for the run (fs.make_temp_dir), and removes it.

This gate reads every tests/**/*.ae, std/**/test_*.ae and
contrib/**/test_*.ae and fails on a fixed name under the temp directory that
the program writes. With comments set aside:

  * the temp directory is `/tmp`, `os.temp_dir()`, or a variable assigned
    from `os.temp_dir()`;
  * a path under it is a string literal that starts there
    (`"/tmp/x"`, `"${tmp}/x"`, `"${os.temp_dir()}/x"`), `path.join(<temp
    directory>, "x")`, a variable assigned one of those, or a literal built
    on such a variable (`"${base}/sub"`);
  * its name (the first part under the temp directory) is fixed unless it
    interpolates `os.getpid()`, a variable assigned from something that
    names `getpid` or `make_temp`, or a value this file does not assign;
  * it is written when it is the path a creating call is given first: a
    callee whose name has the word `write` or `mkdir` in it
    (`fs.write_atomic`, `io.fd_open_write`, a C shim's
    `probe_write_binary`), or is `append`, `append_file`, `create*` or
    `touch`; `open` with a mode that has `w`, `a` or `+`; or the
    destination (second path) of `copy`, `copy_tree`, `move`, `rename`,
    `symlink`, `hard_link` or `link`; or a word of a `system` command.
    `mkdir_p`, `copy_tree` and `system` make every directory on the way,
    so any path under the name counts; the others make only the last part,
    so the path counts when it is the name itself (a write into a directory
    that never exists makes nothing).

A path a program builds another way (an `ae build -o` or ffmpeg argument
list) is not seen. A name written on purpose that cannot collide (a write
that must fail) carries a `tmp-ok: <why>` note on the line that spells it
or on a comment line right above it.

Run from the repository root; exit 1 listing every offender.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WAIVER = "tmp-ok:"

# The last part of a callee's name that creates what its path names.
CREATES = re.compile(r"(?:^|_)p?write(?:_|$)|^append(?:_file)?$|mkdir|^create|^(?:touch|system)$")
# Calls from one path to another (a string.copy(s) has one argument).
TWO_PATHS = re.compile(r"^(?:copy|copy_tree|copy_file|move|rename|symlink|hard_link|link)$")
# Callees that also make every directory on the way to the path they name.
PARENTS = re.compile(r"mkdir_p|makedirs|mkdirs|create_dir_all|copy_tree|^system$")
# An open mode that writes.
WRITE_MODE = re.compile(r"[wa+]")
# Names that make a value unique to the run.
UNIQUE_WORDS = ("getpid", "make_temp")
DECL_WORDS = ("const", "let", "var", "mut", "export", "pub")
FN_WORDS = ("fn", "func", "export", "pub")
NOT_CALLEES = ("if", "while", "for", "match", "return", "switch", "elif", "else", "and", "or", "not")
OPS2 = ("==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "->", "=>", "&&", "||", ">>")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
BARE_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*$")

ROOT_DIR = "root"      # the temp directory itself
UNIQUE = "unique"      # a value unique to the run (getpid, make_temp_dir)
OTHER = "other"        # some other value this file assigns


class TempPath(object):
    """A path under the temp directory: whether its first part is fixed,
    how many parts it has under the temp directory, that first part, and
    the line that spells it."""

    def __init__(self, fixed, depth, name, line):
        self.fixed = fixed
        self.depth = depth
        self.name = name
        self.line = line


# ---- tokens ---------------------------------------------------------------

def tokens(src):
    """(kind, text, line, column) for the code in an Aether source, with
    comments and heredoc bodies left out. kind is 'str' (text is the
    literal's content, `${...}` kept as written), 'id' (a dotted name),
    'nl', or 'p' (punctuation and operators)."""
    out = []
    i = 0
    n = len(src)
    line = 1
    col0 = 0  # index where the current line starts
    while i < n:
        c = src[i]
        if c == "\n":
            out.append(("nl", "\n", line, i - col0))
            line += 1
            i += 1
            col0 = i
        elif c in " \t\r":
            i += 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            line += src.count("\n", i, j)
            k = src.rfind("\n", i, j)
            if k >= 0:
                col0 = k + 1
            i = j
        elif c == '"':
            start_line, start_col = line, i - col0
            text, i = read_string(src, i + 1)
            line += text.count("\n")
            k = src.rfind("\n", 0, i)
            if k >= 0:
                col0 = k + 1
            out.append(("str", text, start_line, start_col))
        elif src.startswith("<<", i) and i + 2 < n and (src[i + 2].isalpha() or src[i + 2] == "_"):
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i + 2:])
            marker = m.group(0)
            out.append(("str", "", line, i - col0))
            j = src.find("\n", i)
            while j >= 0:
                line += 1
                col0 = j + 1
                k = src.find("\n", j + 1)
                body = src[j + 1:k if k >= 0 else n]
                j = k
                if body.strip() == marker:
                    break
            i = n if j < 0 else j
        elif c == "`":
            j = src.find("`", i + 1)
            j = n if j < 0 else j
            out.append(("id", src[i + 1:j], line, i - col0))
            i = j + 1
        elif c.isalpha() or c == "_":
            m = IDENT.match(src, i)
            out.append(("id", m.group(0), line, i - col0))
            i = m.end()
        elif c.isdigit():
            m = re.match(r"[0-9A-Za-z_.]+", src[i:])
            out.append(("p", m.group(0), line, i - col0))
            i += len(m.group(0))
        else:
            two = src[i:i + 2]
            if two in OPS2:
                out.append(("p", two, line, i - col0))
                i += 2
            else:
                out.append(("p", c, line, i - col0))
                i += 1
    return out


def read_string(src, i):
    """The content of the string literal whose opening quote is just before
    `i`, and the index past its closing quote. Inside `${...}` a quote opens
    a nested string, as in the lexer."""
    out = []
    depth = 0
    n = len(src)
    while i < n:
        c = src[i]
        if depth == 0 and c == '"':
            return "".join(out), i + 1
        if c == "\\" and i + 1 < n:
            if depth > 0 and src[i + 1] == '"':
                i += 1           # an escaped quote opening a nested string
                continue
            out.append(src[i:i + 2])
            i += 2
            continue
        if src.startswith("${", i):
            depth += 1
            out.append("${")
            i += 2
            continue
        if depth > 0 and c == "{":
            depth += 1
        elif depth > 0 and c == "}":
            depth -= 1
        elif depth > 0 and c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), n


def segments(text):
    """A literal's content as [('lit', s) | ('expr', e)]."""
    out = []
    i = 0
    lit = []
    while i < len(text):
        if text.startswith("${", i):
            depth = 1
            j = i + 2
            while j < len(text) and depth:
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                j += 1
            if lit:
                out.append(("lit", "".join(lit)))
                lit = []
            out.append(("expr", text[i + 2:j - 1].strip()))
            i = j
        else:
            lit.append(text[i])
            i += 1
    if lit:
        out.append(("lit", "".join(lit)))
    return out


def parts(segs):
    """Split segments on `/` into path parts, each a list of segments."""
    comps = [[]]
    for kind, s in segs:
        if kind == "expr":
            comps[-1].append((kind, s))
            continue
        pieces = s.split("/")
        for k, piece in enumerate(pieces):
            if k:
                comps.append([])
            if piece:
                comps[-1].append(("lit", piece))
    return [c for c in comps if c]


def spell(comp):
    return "".join(s if k == "lit" else "${%s}" % s for k, s in comp)


# ---- values ---------------------------------------------------------------

def is_temp_dir_call(e):
    return re.fullmatch(r"(?:[A-Za-z_][A-Za-z0-9_]*\.)*temp_dir\s*\(\s*\)", e) is not None


def interp_value(e, env):
    """What an interpolated expression is: ROOT_DIR, a TempPath, UNIQUE,
    OTHER, or None when this file does not say."""
    if is_temp_dir_call(e):
        return ROOT_DIR
    if any(w in e for w in UNIQUE_WORDS):
        return UNIQUE
    if BARE_IDENT.match(e):
        return env.get(e)
    return None


def per_run(comp, env):
    """Whether a path part carries something unique to the run."""
    for kind, s in comp:
        if kind != "expr":
            continue
        v = interp_value(s, env)
        if v is None or v == UNIQUE:
            return True
        if isinstance(v, TempPath) and not v.fixed:
            return True
    return False


def literal_path(text, line, env):
    """The TempPath a string literal names, or None."""
    segs = segments(text)
    if not segs:
        return None
    kind, s = segs[0]
    if kind == "lit" and s.startswith("/tmp/"):
        rest = [("lit", s[5:])] + segs[1:]
        base = None
    elif kind == "expr" and (len(segs) == 1 or (segs[1][0] == "lit" and segs[1][1].startswith("/"))):
        base = interp_value(s, env)
        if base != ROOT_DIR and not isinstance(base, TempPath):
            return None
        rest = segs[1:]
    else:
        return None
    comps = parts(rest)
    if isinstance(base, TempPath):
        return TempPath(base.fixed, base.depth + len(comps), base.name, base.line)
    if not comps:
        return None
    return TempPath(not per_run(comps[0], env), len(comps), spell(comps[0]), line)


def split_args(toks):
    """Top-level comma-separated arguments of a call's token list."""
    args, cur, depth = [], [], 0
    for t in toks:
        if t[0] == "p" and t[1] in "([{":
            depth += 1
        elif t[0] == "p" and t[1] in ")]}":
            depth -= 1
        if depth == 0 and t[0] == "p" and t[1] == ",":
            args.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        args.append(cur)
    return [[t for t in a if t[0] != "nl"] for a in args]


def value(toks, env):
    """What an expression's tokens are: ROOT_DIR, a TempPath, UNIQUE,
    OTHER, or None when this file does not say."""
    toks = [t for t in toks if t[0] != "nl"]
    if not toks:
        return None
    if len(toks) == 1 and toks[0][0] == "str":
        p = literal_path(toks[0][1], toks[0][2], env)
        if p is not None:
            return p
        segs = segments(toks[0][1])
        if toks[0][1] in ("/tmp", "/tmp/") or (
                len(segs) == 1 and segs[0][0] == "expr" and interp_value(segs[0][1], env) == ROOT_DIR):
            return ROOT_DIR
    if len(toks) == 1 and toks[0][0] == "id":
        return env.get(toks[0][1])
    if toks[0][0] == "id" and len(toks) >= 3 and toks[1][1] == "(" and toks[-1][1] == ")":
        callee = toks[0][1].split(".")[-1]
        inner = toks[2:-1]
        if callee == "temp_dir" and not inner:
            return ROOT_DIR
        if callee == "join":
            args = split_args(inner)
            if len(args) == 2 and len(args[1]) == 1 and args[1][0][0] == "str":
                base = value(args[0], env)
                rel = args[1][0]
                if base == ROOT_DIR:
                    comps = parts(segments(rel[1]))
                    if comps:
                        return TempPath(not per_run(comps[0], env), len(comps), spell(comps[0]), rel[2])
                if isinstance(base, TempPath):
                    return TempPath(base.fixed, base.depth + len(parts(segments(rel[1]))),
                                    base.name, base.line)
    for t in toks:
        if t[0] == "id" and (any(w in t[1] for w in UNIQUE_WORDS) or env.get(t[1]) == UNIQUE):
            return UNIQUE
        if t[0] == "str":
            for kind, s in segments(t[1]):
                if kind == "expr" and interp_value(s, env) == UNIQUE:
                    return UNIQUE
    return OTHER


# ---- statements -----------------------------------------------------------

def statements(toks):
    """Split tokens into statements: a line end or `;` outside ( and [,
    and every { and } (so a block's first line starts a statement)."""
    out, cur, depth = [], [], 0
    for t in toks:
        if t[0] == "p" and t[1] in "([":
            depth += 1
        elif t[0] == "p" and t[1] in ")]":
            depth = max(0, depth - 1)
        if depth == 0 and (t[0] == "nl" or (t[0] == "p" and t[1] in ";{}")):
            if cur:
                out.append(cur)
            cur = []
            continue
        cur.append(t)
    if cur:
        out.append(cur)
    return out


def calls(stmt):
    """(callee, call line, argument token lists) for every call in a
    statement, nested ones included."""
    out = []
    for k, t in enumerate(stmt):
        if t[0] != "id" or k + 1 >= len(stmt) or stmt[k + 1][1] != "(":
            continue
        if t[1] in NOT_CALLEES:
            continue
        depth = 0
        for j in range(k + 1, len(stmt)):
            if stmt[j][0] == "p" and stmt[j][1] in "([{":
                depth += 1
            elif stmt[j][0] == "p" and stmt[j][1] in ")]}":
                depth -= 1
                if depth == 0:
                    out.append((t[1], t[2], split_args(stmt[k + 2:j])))
                    break
    return out


def binding(stmt):
    """(names, rhs tokens) when a statement assigns, else None."""
    k = 0
    while k < len(stmt) and stmt[k][0] == "id" and stmt[k][1] in DECL_WORDS:
        k += 1
    names = []
    while k < len(stmt) and stmt[k][0] == "id":
        names.append(stmt[k][1])
        k += 1
        if k < len(stmt) and stmt[k][1] == ",":
            k += 1
            continue
        break
    if names and k < len(stmt) and stmt[k][1] == "=":
        return names, stmt[k + 1:]
    return None


def creates(name, args):
    """Whether a call to `name` with these arguments creates a path it names."""
    if CREATES.search(name):
        return True
    if TWO_PATHS.match(name):
        return len(args) >= 2
    if name == "open":
        return any(t[0] == "str" and WRITE_MODE.search(t[1]) for a in args[1:] for t in a)
    return False


def shell_words(text):
    """The words of a shell command held in a literal's content, a `${...}`
    kept whole."""
    words, cur, depth, i = [], [], 0, 0
    while i < len(text):
        if text.startswith("${", i):
            depth += 1
            cur.append("${")
            i += 2
            continue
        c = text[i]
        if depth:
            depth += {"{": 1, "}": -1}.get(c, 0)
        elif c.isspace() or c in ";|&<>()'\"\\":
            if cur:
                words.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    if cur:
        words.append("".join(cur))
    return words


def written(callee, args, env):
    """The fixed TempPaths a creating call writes: the path it is given
    first, the destination of a two-path call, or a word of a shell
    command."""
    name = callee.split(".")[-1]
    if not creates(name, args):
        return []
    if name == "system":
        paths = [literal_path(w, t[2], env)
                 for a in args for t in a if t[0] == "str" for w in shell_words(t[1])]
        return [p for p in paths if p is not None and p.fixed]
    dest = args[1:2] if TWO_PATHS.match(name) else args[:1]
    parents = PARENTS.search(name) is not None
    found = []
    for arg in dest:
        v = value(arg, env)
        if isinstance(v, TempPath) and v.fixed and (parents or v.depth == 1):
            found.append(v)
    return found


def check_source(src):
    """Offences in one Aether source as (lineno, message)."""
    lines = src.split("\n")
    found = {}
    env = {}
    top = {}
    for stmt in statements(tokens(src)):
        first = stmt[0]
        # A function header at the left margin starts a fresh scope: the
        # names assigned in the last function are gone, the file's
        # top-level ones stay.
        head = [t for t in stmt[:3] if not (t[0] == "id" and t[1] in FN_WORDS)]
        if first[3] == 0 and len(head) > 1 and head[0][0] == "id" and head[1][1] == "(":
            env = dict(top)
        for callee, cline, args in calls(stmt):
            for p in written(callee, args, env):
                key = (p.line, p.name)
                if key not in found:
                    found[key] = "`%s` is a fixed name under the temp directory, and %s() on line %d writes it: " \
                                 "name it with this process (_${os.getpid()}) or make it with fs.make_temp_dir" \
                                 % (p.name, callee, cline)
        b = binding(stmt)
        if b:
            names, rhs = b
            v = value(rhs, env) if len(names) == 1 else (
                UNIQUE if value(rhs, env) == UNIQUE else OTHER)
            for nm in names:
                env[nm] = v
                if first[3] == 0:
                    top[nm] = v
    out = []
    for (n, _name), msg in sorted(found.items()):
        here = lines[n - 1] if n - 1 < len(lines) else ""
        above = lines[n - 2].strip() if n >= 2 else ""
        if WAIVER in here or (above.startswith("//") and WAIVER in above):
            continue
        out.append((n, msg))
    return out


def test_programs(root):
    out = []
    for dirpath, _, names in os.walk(os.path.join(root, "tests")):
        for n in names:
            if n.endswith(".ae"):
                out.append(os.path.join(dirpath, n))
    for sub in ("std", "contrib"):
        for dirpath, _, names in os.walk(os.path.join(root, sub)):
            for n in names:
                if n.startswith("test_") and n.endswith(".ae"):
                    out.append(os.path.join(dirpath, n))
    return sorted(out)


def main():
    # A name can be UTF-8 (test_utf8_paths.ae); a Windows console is not.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="backslashreplace")
    offences = []
    for path in test_programs(ROOT):
        with open(path, encoding="utf-8", errors="replace") as f:
            src = f.read()
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for n, msg in check_source(src):
            offences.append("%s:%d: %s" % (rel, n, msg))
    if offences:
        print("ae tmp: %d fixed name(s) under the temp directory that a test writes (#2771):"
              % len(offences))
        for o in offences:
            print("  " + o)
        print("  two sweeps on one machine write the same file; mark a write that must fail")
        print("  (and so cannot collide) `tmp-ok: <why>`.")
        return 1
    print("ae tmp: every test program writes under the temp directory with names of its own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
