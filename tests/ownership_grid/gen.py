#!/usr/bin/env python3
"""Generator of the ownership grid (stage 1 of docs/design/ownership-model.md).

A cell is one value KIND held in one PLACE and moved by one TRANSFER. For
every meaningful combination this module writes one standalone Aether
program that

  1. runs the shape inside a function called 100 times per round;
  2. checks every value it can read against the one the shape stored
     (expected values come from the construction, never from running main);
     a mismatch prints "WRONG: ..." and exits 12;
  3. measures mem.steady_growth over rounds of 100 calls and expects 0;
     growth prints "LEAK: <n> bytes per 100 calls" and exits 13;
  4. is built a second time by the runner against poison_alloc.c, which
     poisons and never reuses freed blocks and stops a double free.

`cells()` returns every cell; `skipped()` every combination left out, with
the reason. run.py builds, runs and classifies them; `python gen.py --list`
prints the cell ids and `python gen.py --skips` the skip list.

The axes are the stage-1 grid's (kinds K1-K8, places P1-P13, transfers
T1-T11), extended with the shapes the comments on PR #2883 found by hand, and a producer axis (the S* kinds:
one real std function per class of docs/design/ownership-r1-inventory.md)
crossed with the main places and transfers. See README.md.
"""

import sys

CALLS = 100  # calls of the shape per round; growth is reported per round

# ---------------------------------------------------------------------------
# Values. A tag names one fresh value; its strings are built from the
# parameter `w` ("w"), because string.concat of two literals folds to a
# literal that owns nothing.

SUFFIX = {"a": "#a", "b": "#bb", "c": "#ccc", "z": "#z"}
NUM = {"a": 1, "b": 2, "c": 3, "z": 0}


def text(tag, part=""):
    return "w" + SUFFIX[tag] + part


class Gen:
    """Collects one program: module declarations, fresh names."""

    def __init__(self, cell):
        self.cell = cell
        self.decls = {}       # key -> text, in first-use order
        self.imports = ["std.mem", "std.string"]
        self.counter = 0
        self.main_lines = []

    def name(self, base):
        self.counter += 1
        return "%s%d" % (base, self.counter)

    def decl(self, key, body):
        if key not in self.decls:
            self.decls[key] = body

    def need_import(self, mod):
        if mod not in self.imports:
            self.imports.append(mod)


def block(lines, depth):
    """Indent a list of statement lines (which may hold nested lines)."""
    pad = "    " * depth
    out = []
    for ln in lines:
        for sub in ln.split("\n"):
            out.append(pad + sub if sub else "")
    return out


# ---------------------------------------------------------------------------
# Kinds


class Kind:
    id = ""
    title = ""
    ty = ""           # the Aether type
    zero = None       # constant initializer of a module var, None if none can be declared
    is_string = False

    def fresh(self, g, tag):
        """(statements, expression) of a fresh value of this kind."""
        raise NotImplementedError

    def check(self, g, expr, tag, what):
        """Statements checking that `expr` holds the value `tag`."""
        raise NotImplementedError

    def bind_local(self, name, expr):
        return "%s = %s" % (name, expr)


class ArrayKind(Kind):
    """An inferred binding of a named array is a pointer to its first element
    (array-to-pointer decay), so an array local is declared with its type,
    which copies the elements."""

    def bind_local(self, name, expr):
        return "%s %s = %s" % (self.ty, name, expr)


def need_doc(g):
    g.decl("struct Doc", "struct Doc {\n    name: string\n    n: int\n}")


class K1(Kind):
    id, title, ty, zero, is_string = "K1", "fresh string (`string.concat`)", "string", '""', True

    def fresh(self, g, tag):
        return [], 'string.concat(w, "%s")' % SUFFIX[tag]

    def check(self, g, expr, tag, what):
        return ['check(%s == "%s", "%s")' % (expr, text(tag), what)]


class K1Ptr(K1):
    """K1 read back from a container: the element comes back as a `ptr`."""

    def check(self, g, expr, tag, what):
        return ['check(string.equals(%s, "%s") == 1, "%s")' % (expr, text(tag), what)]


class K2(Kind):
    id, title, ty, zero = "K2", "`string?` holding a fresh string", "string?", "none"

    def fresh(self, g, tag):
        return [], 'string.concat(w, "%s")' % SUFFIX[tag]

    def check(self, g, expr, tag, what):
        return ['check(%s == "%s", "%s")' % (paren_unwrap(expr), text(tag), what)]

    def bind_local(self, name, expr):
        return "string? %s = %s" % (name, expr)


def paren_unwrap(expr):
    return "%s!" % expr if expr.isidentifier() else "(%s)!" % expr


class K3(Kind):
    id, title, ty, zero = "K3", "closure capturing a fresh string", "fn", "null"

    # The closure hands back the string it captured and the check compares its
    # characters: the poisoning allocator keeps a freed string's header, so a
    # length read through a freed environment would still come out right.
    def fresh(self, g, tag):
        c = "c_" + tag
        return (['%s = string.concat(w, "%s")' % (c, SUFFIX[tag])],
                "|| { return %s }" % c)

    def check(self, g, expr, tag, what):
        r = g.name("r")
        return ["string %s = call(%s)" % (r, expr),
                'check(%s == "%s", "%s")' % (r, text(tag), what)]


class K4(ArrayKind):
    id, title, ty = "K4", "`fn[2]` of capturing closures", "fn[2]"

    def fresh(self, g, tag):
        c, c1 = "c_" + tag, "c_%s1" % tag
        return (['%s = string.concat(w, "%s")' % (c, SUFFIX[tag]),
                 '%s = string.concat(w, "%s1")' % (c1, SUFFIX[tag])],
                "[|| { return %s }, || { return %s }]" % (c, c1))

    def check(self, g, expr, tag, what):
        r0, r1 = g.name("r"), g.name("r")
        return ["string %s = call(%s[0])" % (r0, expr),
                "string %s = call(%s[1])" % (r1, expr),
                'check(%s == "%s" && %s == "%s", "%s")' % (r0, text(tag), r1, text(tag, "1"), what)]


class K5(Kind):
    id, title, ty, zero = "K5", "struct owning a string field (`Doc`)", "Doc", 'Doc { name: "", n: 0 }'

    def fresh(self, g, tag):
        need_doc(g)
        return [], 'Doc { name: string.concat(w, "%s"), n: %d }' % (SUFFIX[tag], NUM[tag])

    def check(self, g, expr, tag, what):
        need_doc(g)
        return ['check(%s.name == "%s" && %s.n == %d, "%s")' % (expr, text(tag), expr, NUM[tag], what)]


class K6(Kind):
    id, title, ty = "K6", "tuple `(string, int)` from a function", "(string, int)"

    def fresh(self, g, tag):
        g.decl("fn pair", "pair(w: string, t: string) -> (string, int) {\n"
               "    return string.concat(w, t), string.length(t)\n}")
        return [], 'pair(w, "%s")' % SUFFIX[tag]

    def check(self, g, expr, tag, what):
        s, n = g.name("s"), g.name("n")
        return ["%s, %s = %s" % (s, n, expr),
                'check(%s == "%s" && %s == %d, "%s")' % (s, text(tag), n, len(SUFFIX[tag]), what)]


class K7(ArrayKind):
    id, title, ty = "K7", "`string[2]`", "string[2]"

    def fresh(self, g, tag):
        return [], '[string.concat(w, "%s"), string.concat(w, "%s1")]' % (SUFFIX[tag], SUFFIX[tag])

    def check(self, g, expr, tag, what):
        return ['check(%s[0] == "%s" && %s[1] == "%s", "%s")' % (expr, text(tag), expr, text(tag, "1"), what)]


class K8(ArrayKind):
    id, title, ty = "K8", "array of string-owning structs (`Doc[2]`)", "Doc[2]"

    def fresh(self, g, tag):
        need_doc(g)
        return [], ('[Doc { name: string.concat(w, "%s"), n: %d }, Doc { name: string.concat(w, "%s1"), n: %d }]'
                    % (SUFFIX[tag], NUM[tag], SUFFIX[tag], NUM[tag]))

    def check(self, g, expr, tag, what):
        need_doc(g)
        return ['check(%s[0].name == "%s" && %s[1].name == "%s", "%s")'
                % (expr, text(tag), expr, text(tag, "1"), what)]


class K9(Kind):
    """A named function used as a closure value: no environment, only a box."""
    id, title, ty, zero = "K9", "named function as a closure value (no environment)", "fn", "null"

    def fresh(self, g, tag):
        g.decl("fn named_" + tag, "named_%s() -> int {\n    return %d\n}" % (tag, len(text(tag))))
        return [], "named_" + tag

    def check(self, g, expr, tag, what):
        r = g.name("r")
        return ["int %s = call(%s)" % (r, expr),
                'check(%s == %d, "%s")' % (r, len(text(tag)), what)]


# ---- producers: a string a std C function makes (the R1 inventory) -------
#
# docs/design/ownership-r1-inventory.md classes every std C function that
# returns a string by the shape of what it returns: A, a counted string the
# caller owns; A~, a counted string someone else holds; B, a plain malloc'd
# buffer the caller owns; C, a pointer into memory C keeps; D, a literal; and
# tuples carrying one of those in a slot. A producer kind is K1 with its
# value made by one real std function of a class instead of string.concat,
# crossed with the main places and transfers only (PRODUCER_PLACES,
# PRODUCER_TRANSFERS), so that R1's change to the producers shows in the grid.
# Its values are checked with string.equals, which reads a `ptr` (a list
# element) as well as a string.

TAG_WORD = {"a": "a", "b": "bb", "c": "ccc", "z": "z"}


def data_file(g, tag):
    """A file main writes, named after the cell so parallel cells do not share it."""
    name = "grid_%s_%s.txt" % (g.cell.lower().replace("-", "_"), tag)
    g.need_import("std.fs")
    g.main_lines.append('fs.write("%s", "%s")' % (name, text(tag)))
    return name


class Producer(K1):
    pclass = ""
    function = ""     # the C function
    module = ""       # its std module
    shown = ""        # how the cell spells the call
    modules = ()

    def expected(self, tag):
        return text(tag)

    def check(self, g, expr, tag, what):
        return ['check(string.equals(%s, "%s") == 1, "%s")' % (expr, self.expected(tag), what)]

    def fresh(self, g, tag):
        for m in self.modules:
            g.need_import(m)
        return self.make(g, tag)


class SA1(Producer):
    id, pclass, function, module = "SA1", "A", "string_replace", "std.string"
    title = "string from `string.replace` (class A: counted, the caller owns it)"

    def make(self, g, tag):
        return [], 'string.replace(w, "w", "%s")' % text(tag)


class SA2(Producer):
    id, pclass, function, module = "SA2", "A", "string_concat_wrapped", "std.string"
    title = "string from `string.concat_wrapped` (class A: counted, the caller owns it)"

    def make(self, g, tag):
        return [], 'string.concat_wrapped(w, "%s")' % SUFFIX[tag]


class SAR(Producer):
    id, pclass, function, module = "SAR", "A~", "string_list_get", "std.collections"
    title = "string from `string_list_get` (class A~: counted, the list holds it)"
    modules = ("std.collections",)

    def make(self, g, tag):
        sl = "sl_" + tag
        return (["%s = collections.string_list_new()" % sl,
                 "defer collections.string_list_free(%s)" % sl,
                 'collections.string_list_add(%s, string.concat(w, "%s"))' % (sl, SUFFIX[tag])],
                "collections.string_list_get(%s, 0)" % sl)


class SB1(Producer):
    id, pclass, function, module = "SB1", "B", "path_join", "std.path"
    title = "string from `path.join` (class B: a plain malloc'd buffer the caller owns)"
    modules = ("std.path",)

    def expected(self, tag):
        return "w/" + TAG_WORD[tag]

    def make(self, g, tag):
        return [], 'path.join(w, "%s")' % TAG_WORD[tag]


class SB2(Producer):
    id, pclass, function, module = "SB2", "B", "path_rel", "std.path"
    title = "string from `path.rel` (class B: a plain malloc'd buffer the caller owns)"
    modules = ("std.path",)

    def expected(self, tag):
        return TAG_WORD[tag]

    def make(self, g, tag):
        return [], 'path.rel(w, "w/%s")' % TAG_WORD[tag]


class SC1(Producer):
    id, pclass, function, module = "SC1", "C", "string_seq_head", "std.string"
    title = "string from `string.seq_head` (class C: a pointer into the sequence's cell)"

    def make(self, g, tag):
        sq = "sq_" + tag
        return (['%s = string.seq_cons(string.concat(w, "%s"), string.seq_empty())' % (sq, SUFFIX[tag])],
                "string.seq_head(%s)" % sq)


class SC2(Producer):
    id, pclass, function, module = "SC2", "C", "string_to_cstr", "std.string"
    title = "string from `string.to_cstr` (class C: a pointer into the string's characters)"

    def make(self, g, tag):
        cs = "cs_" + tag
        return (['%s = string.concat(w, "%s")' % (cs, SUFFIX[tag])], "string.to_cstr(%s)" % cs)


class SD1(Producer):
    id, pclass, function, module = "SD1", "D", "path_separator", "std.path"
    title = "string from `path.separator` (class D: a C literal)"
    modules = ("std.path",)

    def check(self, g, expr, tag, what):
        # One character, '/' (47) or '\' (92), whichever the platform uses.
        return ['check(string.length(%s) == 1 && (string.char_at(%s, 0) == 47 || string.char_at(%s, 0) == 92), "%s")'
                % (expr, expr, expr, what)]

    def make(self, g, tag):
        return [], "path.separator()"


class SD2(Producer):
    id, pclass, function, module = "SD2", "D", "http_mime_type", "std.http"
    title = "string from `http.mime_type` (class D: a C literal)"
    modules = ("std.http",)

    def expected(self, tag):
        return "application/octet-stream"

    def make(self, g, tag):
        return [], "http.mime_type(w)"


class ST1(Producer):
    id, pclass, function, module = "ST1", "tuple A", "fs_read_binary_tuple", "std.fs"
    title = "string in the data slot of `fs.read_binary` (a tuple: A data, C error)"
    modules = ("std.fs",)

    def make(self, g, tag):
        d = "d_" + tag
        return (['%s, _, _ = fs.read_binary("%s")' % (d, data_file(g, tag))], d)


class ST2(Producer):
    id, pclass, function, module = "ST2", "tuple B", "fs_realpath_raw", "std.fs"
    title = "string in the path slot of `fs.realpath` (a tuple: B path, D or C error)"
    modules = ("std.fs",)

    def check(self, g, expr, tag, what):
        name = data_file(g, tag)
        return ['check(string.ends_with(%s, "%s") == 1, "%s")' % (expr, name, what)]

    def make(self, g, tag):
        r = "rp_" + tag
        return (['%s, _, _ = fs.realpath("%s")' % (r, data_file(g, tag))], r)


PRODUCERS = [SA1(), SA2(), SAR(), SB1(), SB2(), SC1(), SC2(), SD1(), SD2(), ST1(), ST2()]
PRODUCER_PLACES = ["P1", "P4", "P5", "P8", "P9", "P10L", "P12K"]
PRODUCER_TRANSFERS = ["T1", "T2", "T5", "T7", "T9", "T12"]

KINDS = [K1(), K2(), K3(), K4(), K5(), K6(), K7(), K8(), K9()] + PRODUCERS
KIND = {k.id: k for k in KINDS}
NO_GLOBAL = "no module `var` can hold this kind: a `var` needs a constant initializer, and an array or tuple has none (E0200)"


# ---------------------------------------------------------------------------
# Transfers (the column titles).

TRANSFERS = [
    ("T1", "store, then leave the scope normally"),
    ("T2", "overwrite in place"),
    ("T3", "leave by `continue` and `break`"),
    ("T4", "leave by an early `return` (every other call)"),
    ("T5", "leave by a panic caught by `try`"),
    ("T6", "pass to a function that only reads it"),
    ("T7", "pass to a function that keeps it in a module `var`; read after the scope ended"),
    ("T7S", "pass to a function that keeps it on some paths only"),
    ("T8", "pass to a function that frees it"),
    ("T8S", "pass to a function that frees it on some paths only"),
    ("T9", "return it; the caller reads it"),
    ("T10", "hand it back through an identity function, returned"),
    ("T11", "a `defer` reads it"),
    ("T11R", "a `defer` reads it, and the function returns it"),
    ("T12", "alias: bind a second local to it, overwrite the first"),
    ("T13", "rebind 50,000 times to a closure that holds the previous one"),
    ("T14", "store it into a module `var` directly; read after the scope ended"),
    ("T15", "a store that fails (`list.set` out of range)"),
    ("T16", "captured by a closure, then overwritten, then the closure called"),
]
TRANSFER = dict(TRANSFERS)
# Transfers only the KE cells (an `int!` error slot) take.
KE_TRANSFERS = [
    ("T9M", "propagated by `x!` in a function whose error position a pass-through vetoes"),
    ("T10M", "passed through from C on one path, a fresh error of its own on the other"),
]
TRANSFER.update(dict(KE_TRANSFERS))

# ---------------------------------------------------------------------------
# Helper functions a transfer calls. Each takes the kind's type.


def helper_reads(g, kind):
    lines = ["// Only reads its parameter.", "reads(v: %s) -> int {" % kind.ty]
    lines += block(kind.check(g, "v", "a", "the parameter a reader sees"), 1)
    lines += ["    return 1", "}"]
    g.decl("fn reads", "\n".join(lines))


def helper_keep(g, kind, some=False):
    g.decl("var kept", "var kept: %s = %s" % (kind.ty, kind.zero))
    if some:
        g.decl("fn keep_some", "// Keeps its parameter in a module var on even calls only.\n"
               "keep_some(v: %s, k: int) {\n    if k %% 2 == 0 {\n        kept = v\n    }\n}" % kind.ty)
    else:
        g.decl("fn keep", "// Keeps its parameter in a module var.\nkeep(v: %s) {\n    kept = v\n}" % kind.ty)


def helper_frees(g, some=False):
    if some:
        g.decl("fn frees_some", "// Frees its parameter on even calls only.\n"
               "frees_some(v: string, k: int) {\n    if k % 2 == 0 {\n        string.free(v)\n    }\n}")
    else:
        g.decl("fn frees", "// Frees its parameter.\nfrees(v: string) {\n    string.free(v)\n}")


def helper_id(g, kind):
    g.decl("fn id", "// Hands its parameter back as it came.\nid(v: %s) -> %s {\n    return v\n}" % (kind.ty, kind.ty))


def helper_held(g, kind):
    g.decl("var held", "var held: %s = %s" % (kind.ty, kind.zero))


def helper_boom(g, kind):
    g.decl("fn boom", "// Panics while it holds its parameter.\n"
           "boom(v: %s, k: int) -> int {\n    if k >= 0 {\n        panic(\"stop\")\n    }\n    return 0\n}" % kind.ty)


def catch_lines():
    return ["} catch e {", '    check(e == "stop", "the caught panic")', "}"]


# ---------------------------------------------------------------------------
# Places. A simple place is set up and filled inside the shape function;
# bind/store/read give its operations.


class Place:
    id = ""
    title = ""
    var = None          # local name the place lives in
    pre_read = False    # a read needs statements (a destructure, an unbox)
    global_place = False
    ptr_read = False

    def applies(self, kind):
        return None

    def setup(self, g, kind):
        return []

    def bind(self, g, kind, tag):
        raise NotImplementedError

    def store(self, g, kind, tag):
        raise NotImplementedError

    def read(self, g, kind):
        """(statements, expression)."""
        raise NotImplementedError

    def check(self, g, kind, tag, what):
        pre, expr = self.read(g, kind)
        # A string read back from a container is a `ptr`: compare its characters.
        # (The producer kinds always compare with string.equals.)
        k = K1Ptr() if (self.ptr_read and kind.id == "K1") else kind
        return pre + k.check(g, expr, tag, what)


class P1(Place):
    id, title = "P1", "local"

    def bind(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + [kind.bind_local("x", e)]

    def store(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + ["x = %s" % e]

    def read(self, g, kind):
        return [], "x"


class P2(P1):
    id, title = "P2", "local rebound in a loop body"


class P3(P1):
    id, title = "P3", "local bound only in the branches of an if/else"

    def bind(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        body = pre + [kind.bind_local("x", e)]
        return (["if k % 2 == 0 {"] + block(body, 1) + ["} else {"] + block(body, 1) + ["}"])


class P3B(P1):
    id, title = "P3B", "local bound and used inside one branch of an if"


class P3E(P1):
    id, title = "P3E", "local bound and used inside each branch of an if/else"


class P4(Place):
    id, title = "P4", "field of a local struct"

    def applies(self, kind):
        return None

    def decl_box(self, g, kind):
        if kind.id in ("K5", "K8"):
            need_doc(g)
        g.decl("struct Box", "struct Box {\n    v: %s\n}" % kind.ty)

    def bind(self, g, kind, tag):
        self.decl_box(g, kind)
        pre, e = kind.fresh(g, tag)
        return pre + ["h = Box { v: %s }" % e]

    def store(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + ["h.v = %s" % e]

    def read(self, g, kind):
        return [], "h.v"


class P5(Place):
    id, title = "P5", "element of a fixed-size array local"

    def applies(self, kind):
        if kind.id in ("K4", "K7", "K8"):
            return "arrays are one-dimensional: an array literal cannot hold an array"
        if kind.id == "K9":
            return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
        if kind.id == "K2":
            return "an array of optionals cannot be declared: `let xs: string?[2] = ...` does not parse (E0100)"
        return None

    def bind(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        pz, ez = kind.fresh(g, "z")
        return pre + pz + ["xs = [%s, %s]" % (e, ez)]

    def store(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + ["xs[0] = %s" % e]

    def read(self, g, kind):
        return [], "xs[0]"


class P5L(P5):
    id, title = "P5L", "element of a fixed-size array local rebound in a loop body"


class P6(Place):
    id, title = "P6", "slot of a tuple local"
    pre_read = True

    def applies(self, kind):
        if kind.id == "K9":
            return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
        return None

    def slot_fn(self, g, kind, tag):
        name = "slot_" + tag
        pre, e = kind.fresh(g, tag)
        body = pre + ["return %s, 7" % e]
        g.decl("fn " + name, "// A tuple whose first slot holds a fresh value.\n%s(w: string) -> (%s, int) {\n%s\n}"
               % (name, kind.ty, "\n".join(block(body, 1))))
        return name

    def bind(self, g, kind, tag):
        return ["t = %s(w)" % self.slot_fn(g, kind, tag)]

    def store(self, g, kind, tag):
        return ["t = %s(w)" % self.slot_fn(g, kind, tag)]

    def read(self, g, kind):
        x, n = g.name("x"), g.name("n")
        return ["%s, %s = t" % (x, n), 'check(%s == 7, "the second slot")' % n], x

    def check(self, g, kind, tag, what):
        # Destructured twice: a destructure that takes the slot's value, or
        # leaves the tuple holding a view of it, shows on the second.
        pre1, x1 = self.read(g, kind)
        pre2, x2 = self.read(g, kind)
        return (pre1 + kind.check(g, x1, tag, what) +
                pre2 + kind.check(g, x2, tag, what + ", destructured again"))


class P7(Place):
    id, title = "P7", "optional payload"

    def applies(self, kind):
        if kind.id == "K1":
            return "the same cell as K2-P1 (a `string?` local)"
        if kind.id == "K2":
            return "`T??` is rejected: an optional is a single presence layer"
        if kind.id == "K9":
            return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
        return None

    def bind(self, g, kind, tag):
        if kind.id in ("K5", "K8"):
            need_doc(g)
        pre, e = kind.fresh(g, tag)
        return pre + ["let o: %s? = %s" % (kind.ty, e)]

    def store(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + ["o = %s" % e]

    def read(self, g, kind):
        return [], "o!"


class P8(Place):
    id, title = "P8", "module `var`"
    global_place = True

    def applies(self, kind):
        if kind.zero is None:
            return NO_GLOBAL
        if kind.id == "K9":
            return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
        return None

    def setup(self, g, kind):
        if kind.id == "K5":
            need_doc(g)
        g.decl("var g", "var g: %s = %s" % (kind.ty, kind.zero))
        return []

    def bind(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre + ["g = %s" % e]

    store = bind

    def read(self, g, kind):
        return [], "g"


class P10L(Place):
    id, title = "P10L", "element of a `std.list` (closures through `box_closure`)"
    pre_read = True
    ptr_read = True

    def applies(self, kind):
        if not (kind.is_string or kind.id in ("K3", "K9")):
            return "a list slot holds a string, an int or a pointer; a closure goes in through `box_closure`"
        return None

    def setup(self, g, kind):
        g.need_import("std.list")
        return ["l = list.new()", "defer list.free(l)"]

    def value(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        if kind.id in ("K3", "K9"):
            e = "box_closure(%s)" % e
        return pre, e

    def bind(self, g, kind, tag):
        pre, e = self.value(g, kind, tag)
        return pre + ["list.add(l, %s)" % e]

    def store(self, g, kind, tag):
        pre, e = self.value(g, kind, tag)
        return pre + ["list.set(l, 0, %s)" % e]

    def read(self, g, kind):
        if kind.id in ("K3", "K9"):
            f = g.name("f")
            return ["fn %s = unbox_closure(list.get_raw(l, 0))" % f], f
        e = g.name("e")
        return ["%s, _ = list.get(l, 0)" % e], e


class P10M(P10L):
    id, title = "P10M", "value of a `std.map` (closures through `box_closure`)"

    def applies(self, kind):
        if kind.id not in ("K1", "K3"):
            return "a map value is a string or a pointer; a closure goes in through `box_closure`"
        return None

    def setup(self, g, kind):
        g.need_import("std.map")
        return ["m = map.new()", "defer map.free(m)"]

    def bind(self, g, kind, tag):
        pre, e = self.value(g, kind, tag)
        return pre + ['map.put(m, "k", %s)' % e]

    store = bind

    def read(self, g, kind):
        if kind.id == "K3":
            f = g.name("f")
            return ['fn %s = unbox_closure(map.get_raw(m, "k"))' % f], f
        e = g.name("e")
        return ['%s, _ = map.get(m, "k")' % e], e


class P13G(Place):
    id, title = "P13G", "module `ptr` var holding a closure"
    pre_read = True
    global_place = True

    def applies(self, kind):
        if kind.id not in ("K3", "K9"):
            return "a `ptr` slot is this place only for a closure (the fn -> ptr box)"
        return None

    def setup(self, g, kind):
        g.decl("var slot", "var slot: ptr = null")
        return []

    def boxed(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        if kind.id == "K9":
            # A named function stored bare, the shape the PR comment names
            # (P13F boxes it with box_closure).
            return pre, e
        return pre, "box_closure(%s)" % e

    def bind(self, g, kind, tag):
        pre, e = self.boxed(g, kind, tag)
        return pre + ["slot = %s" % e]

    store = bind

    def read(self, g, kind):
        f = g.name("f")
        return ["fn %s = unbox_closure(slot)" % f], f


class P13D(P13G):
    id, title = "P13D", "module `ptr` var assigned a closure bare (the fn -> ptr coercion, no `box_closure`)"

    def applies(self, kind):
        if kind.id == "K9":
            return "K9's bare store is K9-P13G (a named function stored as it is)"
        if kind.id != "K3":
            return "a `ptr` slot is this place only for a closure (the fn -> ptr box)"
        return None

    def boxed(self, g, kind, tag):
        return kind.fresh(g, tag)


class P13F(P13G):
    id, title = "P13F", "`ptr` field of a local struct holding a closure"
    global_place = False

    def setup(self, g, kind):
        g.decl("struct PtrBox", "struct PtrBox {\n    p: ptr\n}")
        return []

    def boxed(self, g, kind, tag):
        pre, e = kind.fresh(g, tag)
        return pre, "box_closure(%s)" % e

    def bind(self, g, kind, tag):
        pre, e = self.boxed(g, kind, tag)
        return pre + ["h = PtrBox { p: %s }" % e]

    def store(self, g, kind, tag):
        pre, e = self.boxed(g, kind, tag)
        return pre + ["h.p = %s" % e]

    def read(self, g, kind):
        f = g.name("f")
        return ["fn %s = unbox_closure(h.p)" % f], f


class P18(Place):
    id, title = "P18", "string field of an element of a struct array local"

    def applies(self, kind):
        if kind.id != "K1":
            return "the field of an element is a string place: K1 only"
        return None

    def bind(self, g, kind, tag):
        need_doc(g)
        _, e = kind.fresh(g, tag)
        _, ez = kind.fresh(g, "z")
        return ["ds = [Doc { name: %s, n: 1 }, Doc { name: %s, n: 0 }]" % (e, ez)]

    def store(self, g, kind, tag):
        _, e = kind.fresh(g, tag)
        return ["ds[0].name = %s" % e]

    def read(self, g, kind):
        return [], "ds[0].name"


# ---------------------------------------------------------------------------
# The cells the comments on PR #2883 found by hand, before the grid existed.
# "by reading" marks the ones the comment derived without running them.

FOUND = {
    "K3-P5-T10": "closure arrays: return a handed-back element, `return keep(fs[0])` (measured: 9600 bytes per 100 calls)",
    "K3-P5L-T12": "closure arrays: bind an element to a local in a loop, `g = fs[1]; call(g)` (measured: 32000 bytes per 100 calls)",
    "K4-P9W-T1": "closure arrays: a closure writes the array, so it lives in a cell, #2879 (measured: 1600 bytes per 100 calls)",
    "K4-P1-T6": "closure arrays: the whole array passed (by reading)",
    "K4-P9-T9": "closure arrays: the array captured (by reading)",
    "K4-P1-T12": "closure arrays: the whole array copied (leak)",
    "K3-P5-T7": "closure arrays: an element stored (by reading)",
    "K6-P1-T6": "tuples: a tuple local passed as an argument owns nothing (measured with the poisoning allocator's live blocks)",
    "K6-P1-T12": "tuples: a tuple local aliased owns nothing",
    "K6-P9-T1": "tuples: a tuple local captured owns nothing",
    "K6-P1-T11R": "tuples: a defer that destructures a tuple local in a function that returns it (regression R1 of the reverted #2869 fix)",
    "KE-P17-T10M": "tuples: a `T!` function passing an extern's literal errors through vetoes its error position (by reading)",
    "KE-P17-T9M": "tuples: a propagating `x!` in a vetoed function leaks the operand's error (by reading)",
    "KE-P17-T5": "tuples: a non-propagating `x!` panics with a heap error; caught, the reason leaks (by reading)",
    "K1-P5-T7": "a `string[N]` element handed to a function that keeps it dangles once the array's scope ends (a use after free on fed0fbed; the kept string reads freed memory, wrong even without the poisoning allocator)",
    "K3-P13G-T7": "a closure local passed to a function whose `ptr` parameter is stored (a use after free: the stashed closure's environment is freed, and it reads a wrong value even without the poisoning allocator)",
    "K3-P2-T13": "50,000 rebinds of a closure that calls its predecessor overflow the stack at release",
    "K8-P2-T1": "a struct array hoisted into a loop leaks its elements' strings (17500 bytes per 100 calls)",
    "K8-P3E-T1": "a struct array bound and used inside each branch of an if/else leaks its strings (74 bytes per call)",
    "K1-P5-T14": "a `string[N]` element stored into a global string leaks (3600 bytes per 100 calls)",
    "K1-P4-T8S": "a field handed to a function that frees it on some paths only (leak when that path does not run)",
    "K1-P4-T7S": "a field handed to a function that keeps it on some paths only",
    "K1-P18-T8S": "an array element's field handed to a function that frees it on some paths only",
    "K1-P14-T8": "a struct parameter's field handed to a function that frees it (double free)",
    "K1-P15-T8": "an element of a fixed-array parameter handed to a function that frees it (double free)",
    "K5-P16-T2": "a struct stored into an element through a slice leaks the replaced element's string",
    "K8-P9W-T9": "an array of string-owning structs a closure writes, then handed over (leak)",
    "K1-P17-T5": "a string temporary passed to a call that panics, caught (leak: the release is not on the unwind list)",
    "K1-P10L-T15": "a failed adoption (an out-of-range `list_set`) leaks",
    "K5-P5-T16": "a closure capturing an `Item[2]` local, then an element replaced: the closure reads freed strings",
    "K8-P11-T16": "an actor arm closure reading `Item[2]` state (the comment saw a use after free; the generated C no longer compiles)",
    "K4-P11-T16": "an actor arm closure reading `fn[N]` state (the comment: refused by the checker; the checker accepts it and the generated C does not compile)",
    "K7-P1-T5": "a string array bound in a try body that panics leaks its strings (37 bytes per call)",
    "K3-P13G-T1": "a closure stored into a `ptr` slot: the box and its env reference are never freed (86 bytes per store)",
    "K9-P13G-T1": "a bare function stored into a `ptr` slot, without box_closure: the box is never freed",
}

# Cells whose expected value is the design's (R1 to R5) where today's
# documented rule says otherwise. The cell still counts by its run; the note
# says which rule it measures against.


def doc_note(cid):
    kind, place, transfer = cid.split("-")
    if place == "P16" and transfer == "T12":
        return ("Today's rule (memory-management.md, slices): a local bound to a slice element is a view\n"
                "that dangles once the element is replaced; under the design's R2 it holds a reference.")
    if place == "P16" and transfer == "T2":
        return ("Today's rule (memory-management.md, slices): a store through a slice frees nothing, and the\n"
                "array's owner never sees the string it replaced; under the design's R3 the store releases it.")
    if (place == "P8" or transfer in ("T7", "T7S", "T14")) and kind in ("K1", "K2"):
        return ("Today's rule (#2808): a module var never gives back a string it held, so a re-bind leaks\n"
                "the one it replaces; under the design a re-bind is a store, which releases it.")
    return ""


# ---------------------------------------------------------------------------
# Cells


# The status the approved design wants a cell to reach. Under R3 a parameter
# is borrowed, so a function that frees one (`string.free(param)`, on every
# path or on some) frees a reference it does not own, and the checker refuses
# it from stage 4 on: such a cell's target is REFUSED. Every other cell's is
# OK. Better and worse in the check stay relative to the baseline; the report
# says how far each cell is from its target.
REFUSED_NOTE = ("Target (the approved design): REFUSED. A function may not free a value it borrows\n"
                "(a parameter); from stage 4 the checker refuses `string.free` or `release` of a\n"
                "parameter, and says to keep the value (store it) instead.")


def target_of(transfer):
    return "REFUSED" if transfer in ("T8", "T8S") else "OK"


class Cell:
    def __init__(self, kind, place, transfer, source, note=""):
        self.kind = kind
        self.place = place
        self.transfer = transfer
        self.id = "%s-%s-%s" % (kind, place, transfer)
        self.target = target_of(transfer)
        self.file = self.id.lower().replace("-", "_") + ".ae"
        self.source = source
        self.note = note


class Skip:
    def __init__(self, kind, place, transfer, reason):
        self.kind, self.place, self.transfer, self.reason = kind, place, transfer, reason


def check_fn():
    return ("fn check(ok: bool, what: string) {\n"
            "    if !ok {\n"
            '        println("WRONG: ${what}")\n'
            "        exit(12)\n"
            "    }\n"
            "}")


def program(g, kind, place, transfer, shape_lines, round_lines, main_setup=None, round_params="w: string",
            round_args='"w"', note="", calls=CALLS, tries=5):
    """Assemble a whole cell program."""
    cell = g.cell
    head = [
        "// Ownership grid cell %s (tests/ownership_grid, generated by gen.py)." % cell,
        "//   kind:     %s %s" % (kind.id, kind.title),
        "//   place:    %s %s" % (place[0], place[1]),
        "//   transfer: %s %s" % (transfer, TRANSFER[transfer]),
    ]
    if note:
        for ln in note.split("\n"):
            head.append("// " + ln if ln else "//")
    if cell in FOUND:
        head.append("// Found by hand in the comments on PR #2883: %s." % FOUND[cell])
    if target_of(transfer) == "REFUSED":
        head += ["// " + ln for ln in REFUSED_NOTE.split("\n")]
    dn = doc_note(cell) if cell.count("-") == 2 else ""
    if dn:
        head += ["// " + ln for ln in dn.split("\n")]
    head += [
        "// Expected: every value read is the one stored (else WRONG, exit 12),",
        "// and %d calls of the shape do not grow the heap (else LEAK, exit 13)." % calls,
        "// run.py links tests/ownership_grid/poison_alloc.c and runs it a second time",
        "// with OWNERSHIP_GRID_POISON=1, which poisons every freed block.",
        "",
    ]
    out = head
    out += ["import %s" % m for m in g.imports]
    out += ["", "extern exit(code: int)", "", check_fn(), ""]
    for body in g.decls.values():
        out += [body, ""]
    out += shape_lines + [""]
    out += ["round(%s) {" % round_params, "    k = 0", "    while k < %d {" % calls]
    out += block(round_lines, 2)
    out += ["        k = k + 1", "    }", "}", ""]
    out += ["main() {"]
    seen = []
    for ln in g.main_lines:
        if ln not in seen:
            seen.append(ln)
    out += block(seen, 1)
    if main_setup:
        out += block(main_setup, 1)
    out += [
        "    round(%s)" % round_args,
        "    if !mem.heap_in_use_exact() {",
        '        println("OK (growth not measured: the heap count is not exact here)")',
        "        return",
        "    }",
        "    grown = mem.steady_growth(|| { round(%s) }, %d)" % (round_args, tries),
        "    if grown != 0 {",
        '        println("LEAK: ${grown} bytes per %d calls")' % calls,
        "        exit(13)",
        "    }",
        '    println("OK")',
        "}",
    ]
    return "\n".join(out) + "\n"


def shape_fn(ret, body, params="w: string, k: int", name="shape", comment=None):
    lines = []
    if comment:
        lines.append("// " + comment)
    sig = "%s(%s)" % (name, params)
    if ret:
        sig += " -> %s" % ret
    lines.append(sig + " {")
    lines += block(body, 1)
    lines.append("}")
    return lines


# ---- simple places ------------------------------------------------------

SIMPLE = [P1(), P2(), P3(), P3B(), P3E(), P4(), P5(), P5L(), P6(), P7(), P8(), P10L(), P10M(), P13G(), P13D(), P13F(), P18()]


def simple_cell(kind, place, t):
    """Lines of the shape and the round, or a skip reason, for a simple place."""
    g = Gen("%s-%s-%s" % (kind.id, place.id, t))
    reason = place.applies(kind)
    if reason:
        return reason
    loop = place.id in ("P2", "P5L")
    returns_value = t in ("T9", "T10", "T11R")
    ptr_place = place.id in ("P10L", "P10M", "P13G", "P13F")

    # Which transfers a place takes.
    if t == "T13":
        if not (kind.id == "K3" and place.id == "P2"):
            return "the chain is a closure local rebound in a loop: K3-P2 only"
    if t == "T15" and place.id != "P10L":
        return "only a list store can fail (an index out of range)"
    if t in ("T8", "T8S") and not (kind.id == "K1" and not place.ptr_read):
        if kind.is_string:
            return "the element comes back as a `ptr`, which no rule counts"
        return "only a string has a free a callee can call; a part of a value is its own cell (K1 in P4, P5, P14, P15, P18)"
    if place.global_place and t in ("T3", "T4", "T11", "T11R"):
        return "a module var is never left by a scope exit"
    if ptr_place and t in ("T6", "T7", "T7S", "T9", "T10", "T11", "T11R", "T12", "T14") and place.id.startswith("P10"):
        return "the element comes back from the container as a `ptr` (or a closure unboxed from one), which no rule counts"
    if place.id.startswith("P13") and t in ("T7S", "T9", "T10", "T11", "T11R", "T12", "T14"):
        return "the closure is read out of the `ptr` slot by `unbox_closure`, a view no rule counts"
    if place.pre_read and t in ("T11", "T11R"):
        return "the place is read through a statement (a destructure), which a `defer` cannot hold"
    if t in ("T7", "T7S", "T14") and kind.zero is None:
        return NO_GLOBAL
    if t == "T16":
        if place.id == "P1":
            return "the same cell as P9-T2 (a captured local, overwritten after the capture)"
        if place.global_place:
            return "a closure reaches a module var itself; there is no capture"
        if ptr_place:
            return "the place is reached through a pointer; a closure sees its later stores, nothing is copied"
    if t == "T3" and place.id == "P2":
        return "the same cell as P1-T3 (a local bound in a loop body, left by continue and break)"
    if t == "T3" and place.id == "P5L":
        return "the same cell as P5-T3 (the array bound in a loop body, left by continue and break)"
    if place.id == "P13D" and t != "T1":
        return "a bare store into a `ptr` is measured once (T1); the other transfers use `box_closure` (P13G)"
    if kind.id == "K9" and t not in ("T1", "T2"):
        return "K9 (a named function, no environment) is measured for store and overwrite only"
    if t == "T7" and place.id == "P13F":
        return "a closure kept from a `ptr` field is the same keep as from the global slot (P13G-T7)"

    setup = place.setup(g, kind)
    bind = place.bind(g, kind, "a")
    chk = lambda tag, what: place.check(g, kind, tag, what)
    ret = None
    round_lines = ["shape(w, k)"]
    body = []
    last = "j == 3" if loop else None
    note = ""

    def exit_guard(stmts, cond=None):
        conds = [c for c in (cond, last) if c]
        if not conds:
            return stmts
        return ["if %s {" % " && ".join(conds)] + block(stmts, 1) + ["}"]

    if t == "T1":
        body = setup + bind + chk("a", "the value stored") + chk("a", "the value, read again")
    elif t == "T2":
        body = setup + bind + chk("a", "the value stored") + place.store(g, kind, "b") + \
            chk("b", "the value stored over it") + chk("b", "the value stored over it, read again")
    elif t == "T3":
        inner = setup + bind + chk("a", "the value stored") + ["if j == 1 {", "    continue", "}", "break"]
        body = ["j = 0", "while j < 2 {", "    j = j + 1"] + block(inner, 1) + ["}"]
        loop = False
    elif t == "T4":
        ret = "int"
        body = setup + bind + chk("a", "the value stored") + exit_guard(["return 1"], "k % 2 == 0") + \
            chk("a", "the value, on the path that does not return early")
        if not loop:
            body += ["return 0"]
    elif t == "T5":
        inner = setup + bind + chk("a", "the value stored") + exit_guard(['panic("stop")'])
        if loop:
            inner = ["j = 0", "while j < 3 {", "    j = j + 1"] + block(inner, 1) + ["}"]
            loop = False
        body = ["try {"] + block(inner, 1) + catch_lines()
        if place.global_place:
            body += chk("a", "the value stored before the panic, read after the catch")
    elif t == "T6":
        helper_reads(g, kind)
        pre, r = place.read(g, kind)
        n = g.name("n")
        body = setup + bind + pre + ["%s = reads(%s)" % (n, r), 'check(%s == 1, "the reader ran")' % n] + \
            chk("a", "the value, after a reader saw it")
    elif t == "T7" and place.id == "P13G":
        g.decl("fn stash", "// Keeps the pointer it is given in the module var.\nstash(p: ptr) {\n    slot = p\n}")
        pre, e = kind.fresh(g, "a")
        body = pre + ["f = %s" % e, "stash(f)"]
        rpre, r = place.read(g, kind)
        round_lines = ["shape(w, k)"] + rpre + kind.check(g, r, "a", "the stashed closure, after the scope ended")
        note = "A closure local passed to a function whose `ptr` parameter is stored."
    elif t in ("T7", "T7S"):
        some = t == "T7S"
        helper_keep(g, kind, some)
        pre, r = place.read(g, kind)
        call = "keep_some(%s, k)" % r if some else "keep(%s)" % r
        body = setup + bind + pre + [call] + chk("a", "the place, after a function kept it")
        after = kind.check(g, "kept", "a", "the kept value, after the scope ended")
        round_lines = ["shape(w, k)"] + (["if k % 2 == 0 {"] + block(after, 1) + ["}"] if some else after)
    elif t in ("T8", "T8S"):
        some = t == "T8S"
        helper_frees(g, some)
        pre, r = place.read(g, kind)
        body = setup + bind + chk("a", "the value stored") + pre + \
            ["frees_some(%s, k)" % r if some else "frees(%s)" % r] + \
            chk("a", "the place, after a callee freed what it was handed")
    elif t in ("T9", "T10", "T11R"):
        ret = kind.ty
        pre, r = place.read(g, kind)
        if t == "T10":
            helper_id(g, kind)
            r = "id(%s)" % r
        extra = []
        if t == "T11R":
            helper_reads(g, kind)
            extra = ["defer reads(%s)" % place.read(g, kind)[1]]
        # Two paths: every other call returns the place's value, the others
        # leave the place and return a fresh value of their own.
        body = setup + bind + chk("a", "the value stored") + extra + pre + \
            exit_guard(["return %s" % r], "k % 2 == 0")
        pc, ec = kind.fresh(g, "c")
        other = ["// The other path: the place is left, and a fresh value returned."] + pc + ["return %s" % ec]
        if not loop:
            body += other
        v = "v"
        round_lines = [kind.bind_local(v, "shape(w, k)"), "if k % 2 == 0 {"] + \
            block(kind.check(g, v, "a", "the returned value"), 1) + ["} else {"] + \
            block(kind.check(g, v, "c", "the value the other path returned"), 1) + ["}"]
    elif t == "T11":
        helper_reads(g, kind)
        body = setup + bind + ["defer reads(%s)" % place.read(g, kind)[1]] + chk("a", "the value stored")
    elif t == "T12":
        pre, r = place.read(g, kind)
        body = setup + bind + pre + [kind.bind_local("y", r)] + place.store(g, kind, "b") + \
            kind.check(g, "y", "a", "the alias, after the place was overwritten") + \
            chk("b", "the place, after the overwrite")
    elif t == "T13":
        ret = "int"
        pre, e = kind.fresh(g, "a")
        body = pre + ["x = %s" % e] + chk("a", "the first closure") + [
            "j = 0",
            "while j < 50000 {",
            "    j = j + 1",
            "    prev = x",
            "    x = || {",
            "        string s = call(prev)",
            "        return s",
            "    }",
            "}",
            "return 1",
        ]
        loop = False
        note = "The release at scope exit walks a chain 50,000 environments deep."
    elif t == "T14":
        helper_held(g, kind)
        pre, r = place.read(g, kind)
        body = setup + bind + pre + ["held = %s" % r] + chk("a", "the place, after it was stored in a module var")
        round_lines = ["shape(w, k)"] + kind.check(g, "held", "a", "the module var, after the scope ended")
    elif t == "T15":
        pre, e = place.value(g, kind, "b")
        body = setup + bind + pre + ["list.set(l, 5, %s)" % e, 'check(list.size(l) == 1, "the list size")'] + \
            chk("a", "the element, after a store that failed")
    elif t == "T16":
        helper_reads(g, kind)
        pre, r = place.read(g, kind)
        f, n = g.name("f"), g.name("n")
        closure = "%s = || {\n%s\n}" % (f, "\n".join(block(pre + ["return reads(%s)" % r], 1)))
        body = setup + bind + [closure] + place.store(g, kind, "b") + \
            ["int %s = call(%s)" % (n, f), 'check(%s == 1, "the closure read its copy")' % n] + \
            chk("b", "the place, after the overwrite")
    else:
        return "not a transfer of this place"

    if loop:
        body = ["j = 0", "while j < 3 {", "    j = j + 1"] + block(body, 1) + ["}"]
        if ret == "int":
            body += ["return 0"]
        elif ret:
            body += other
    if place.id == "P3E":
        # Bound and used inside each branch. k % 4 < 2 picks the branch, so
        # each branch meets both paths of a transfer that tests k % 2.
        body = ["if k % 4 < 2 {"] + block(body, 1) + ["} else {"] + block(body, 1) + ["}"]
    if place.id == "P3B":
        # k counts calls from 0, so the branch always runs; the compiler cannot know.
        body = ["if k >= 0 {"] + block(body, 1) + ["}"]
        if ret == "int":
            body += ["return 0"]
        elif ret:
            pz, ez = kind.fresh(g, "z")
            body += ["// not reached: the branch always runs"] + pz + ["return %s" % ez]
    calls = 2 if t == "T13" else CALLS
    src = program(g, kind, (place.id, place.title), t,
                  shape_fn(ret, body, comment="The shape: %s." % TRANSFER[t]), round_lines, note=note, calls=calls)
    return src


# ---- P9 / P9W: captured by a closure -----------------------------------


def captured_cell(kind, pid, t):
    g = Gen("%s-%s-%s" % (kind.id, pid, t))
    if kind.id == "K9":
        return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
    write = pid == "P9W"
    pa, ea = kind.fresh(g, "a")
    bind = pa + [kind.bind_local("x", ea)]
    if write:
        pb, eb = kind.fresh(g, "b")
        inner = pb + ["x = %s" % eb] + kind.check(g, "x", "b", "the cell, inside the closure") + ["return 1"]
    else:
        helper_reads(g, kind)
        inner = ["return reads(x)"]
    closure = "f = || {\n%s\n}" % "\n".join(block(inner, 1))
    bind = bind + [closure]
    call_f = ["int n = call(f)", 'check(n == 1, "the closure ran")']
    after_call = kind.check(g, "x", "b", "the local, which the closure rebound") if write else []
    round_lines = ["shape(w, k)"]
    ret = None
    if t == "T1":
        body = bind + call_f + after_call
    elif t == "T2":
        pc, ec = kind.fresh(g, "c")
        body = bind + pc + ["x = %s" % ec] + call_f + after_call
    elif t == "T3":
        inner2 = bind + call_f + ["if j == 1 {", "    continue", "}", "break"]
        body = ["j = 0", "while j < 2 {", "    j = j + 1"] + block(inner2, 1) + ["}"]
    elif t == "T4":
        ret = "int"
        body = bind + call_f + ["if k % 2 == 0 {", "    return 1", "}"] + ["int n2 = call(f)", 'check(n2 == 1, "the closure ran again")', "return 0"]
    elif t == "T5":
        body = ["try {"] + block(bind + call_f + ['panic("stop")'], 1) + catch_lines()
    elif t == "T6":
        g.decl("fn runs", "// Calls the closure it is given, keeps nothing.\nruns(h: fn) -> int {\n    int n = call(h)\n    return n\n}")
        body = bind + ["n = runs(f)", 'check(n == 1, "the closure ran")'] + after_call
    elif t == "T7":
        g.decl("var kept", "var kept: fn = null")
        g.decl("fn keep", "// Keeps the closure in a module var.\nkeep(h: fn) {\n    kept = h\n}")
        body = bind + ["keep(f)"]
        round_lines = ["shape(w, k)", "int n = call(kept)", 'check(n == 1, "the kept closure, after the scope ended")']
    elif t in ("T9", "T10"):
        ret = "fn"
        r = "f"
        if t == "T10":
            g.decl("fn id", "// Hands its parameter back as it came.\nid(h: fn) -> fn {\n    return h\n}")
            r = "id(f)"
        body = bind + ["if k % 2 == 0 {", "    return %s" % r, "}",
                       "// The other path: the closure is left, and another one returned.",
                       "return || { return 1 }"]
        round_lines = ["h = shape(w, k)", "int n = call(h)", 'check(n == 1, "the returned closure")',
                       "int n2 = call(h)", 'check(n2 == 1, "the returned closure, called again")']
    elif t == "T11":
        g.decl("fn runs", "// Calls the closure it is given, keeps nothing.\nruns(h: fn) -> int {\n    int n = call(h)\n    return n\n}")
        body = bind + ["defer runs(f)"] + call_f
    elif t == "T14":
        g.decl("var held", "var held: fn = null")
        body = bind + ["held = f"]
        round_lines = ["shape(w, k)", "int n = call(held)",
                       'check(n == 1, "the closure in the module var, after the scope ended")']
    elif t == "T12":
        body = bind + ["f2 = f", "f = || { return 0 }", "int n = call(f2)", 'check(n == 1, "the alias of the closure")']
    else:
        return None
    title = ("captured by a closure that rebinds it (a shared cell)" if write
             else "captured by a closure that reads it (a copy)")
    return program(g, kind, (pid, title), t, shape_fn(ret, body, comment="The shape: %s." % TRANSFER[t]),
                   round_lines)


P9_TRANSFERS = ["T1", "T2", "T3", "T4", "T5", "T6", "T7", "T9", "T10", "T11", "T12", "T14"]


# ---- P11: actor state; P12: message field --------------------------------

STATE_DECL = {
    "K1": 'state v = ""',
    "K2": "state string? v = none",
    "K3": "state v = || { return 0 }",
    "K4": "state fn[2] v",
    "K5": 'state v = Doc { name: "", n: 0 }',
    "K6": "state (string, int) v",
    "K7": "state string[2] v",
    "K8": "state Doc[2] v",
}

# Why the actor-per-call cells read the heap over 20 windows of 10 calls: an
# actor the scheduler ends keeps its block for the next spawn (a tombstone),
# so the heap count moves by a block in some windows while the actors leak
# nothing. Over 40 windows of 100 calls K1-P11-T1 grew in 9 and shrank by
# 1520 bytes in total; under 24 copies at once, 1 run in 72 met 5 windows in a
# row that moved, which mem.steady_growth reads as growth. A leak grows every
# window, so it still fails; 20 shorter windows make a false one negligible.
P11_T1_NOTE = ("One actor per call: set, asked, then released (destroy_state), and every\n"
               "released actor ended before the next call. The scheduler keeps an ended\n"
               "actor's block for the next spawn, so the heap moves by a block in some\n"
               "windows without a leak: growth is read over 20 windows of 10 calls, and a\n"
               "leak, which grows every window, is still reported.")

ACTOR_NOTE = ("The actor is spawned once in main and asked after each call, so the\n"
              "heap is read with its mailbox drained.")


def actor_program(g, kind, place, t, actor_lines, shape_lines, round_lines, spawn=True, note="", calls=CALLS,
                  tries=5):
    g.decl("message Check", "message Check {}")
    g.decl("message Ack", "message Ack {\n    n: int\n}")
    g.decl("actor Holder", "\n".join(actor_lines))
    return program(g, kind, place, t, shape_lines, round_lines,
                   main_setup=["h = spawn(Holder())"] if spawn else None,
                   round_params="w: string, h: ptr" if spawn else "w: string",
                   round_args='"w", h' if spawn else '"w"',
                   note=(note or (ACTOR_NOTE if spawn else "")), calls=calls, tries=tries)


def state_cell(kind, t):
    pid, title = "P11", "actor state"
    g = Gen("%s-%s-%s" % (kind.id, pid, t))
    if kind.id == "K9":
        return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
    if kind.id in ("K5", "K8"):
        need_doc(g)
    if t in ("T7", "T14") and kind.zero is None:
        return NO_GLOBAL
    if t == "T9" and kind.id != "K1":
        return "a reply carries back a string or a message's first field; measured for K1"
    g.decl("message Set", "message Set {\n    w: string\n}")
    pa, ea = kind.fresh(g, "a")
    bind = pa + ["v = %s" % ea]
    check_tag = "a"
    extra_arms = []
    shape_after = []
    if t in ("T1", "T6", "T7", "T14", "T16"):
        ops = bind
        if t == "T6":
            helper_reads(g, kind)
            ops = bind + ["n = reads(v)", 'check(n == 1, "the reader ran")']
        elif t == "T7":
            helper_keep(g, kind)
            ops = bind + ["keep(v)"]
            shape_after = kind.check(g, "kept", "a", "the kept value, read by the sender")
        elif t == "T14":
            helper_held(g, kind)
            ops = bind + ["held = v"]
            shape_after = kind.check(g, "held", "a", "the module var, read by the sender")
        elif t == "T16":
            helper_reads(g, kind)
            ops = bind + ["f = || { return reads(v) }", "int n = call(f)", 'check(n == 1, "the closure in the arm read the state")']
    elif t == "T2":
        pb, eb = kind.fresh(g, "b")
        ops = bind + kind.check(g, "v", "a", "the state") + pb + ["v = %s" % eb]
        check_tag = "b"
    elif t == "T12":
        pb, eb = kind.fresh(g, "b")
        ops = bind + [kind.bind_local("y", "v")] + pb + ["v = %s" % eb] + \
            kind.check(g, "y", "a", "the alias of the state, after the state was overwritten")
        check_tag = "b"
    elif t == "T9":
        ops = bind
        g.decl("message Get", "message Get {}")
        extra_arms = ["Get() -> {", "    reply v", "}"]
    else:
        return None
    check_arm = ["Check() -> {"] + block(kind.check(g, "v", check_tag, "the state, when asked"), 1) + \
        ["    reply Ack { n: 1 }", "}"]
    set_arm = ["Set(w: w) -> {"] + block(ops, 1) + ["}"]
    actor = ["actor Holder {", "    " + STATE_DECL["K1" if kind.is_string else kind.id], "    receive {"] + \
        block(set_arm + extra_arms + check_arm, 2) + ["    }", "}"]
    ask = ["h ! Set { w: w }", "int n = h ? Check {}", 'check(n == 1, "the actor answered")']
    if t == "T9":
        ask += ["string s = h ? Get {}"] + kind.check(g, "s", "a", "the state, replied")
    if t == "T1":
        g.decl("extern release", "extern scheduler_release_actor(a: ptr) @c_import\n"
               "extern scheduler_reclaim_released() -> int @c_import")
        body = ["h = spawn(Holder())"] + ask + ["let hp: ptr = h", "scheduler_release_actor(hp)",
                                                "// End it now, so no later sweep frees what it held.",
                                                "while scheduler_reclaim_released() > 0 {", "}"]
        return actor_program(g, kind, (pid, title), t, actor,
                             shape_fn(None, body, comment="One actor per call, released when the call is done."),
                             ["shape(w, k)"], spawn=False, calls=10, tries=20,
                             note=P11_T1_NOTE)
    body = ask + shape_after
    return actor_program(g, kind, (pid, title), t, actor,
                         shape_fn(None, body, params="w: string, k: int, h: ptr",
                                  comment="The shape runs in the actor: %s." % TRANSFER[t]),
                         ["shape(w, k, h)"])


P11_TRANSFERS = ["T1", "T2", "T6", "T7", "T9", "T12", "T14", "T16"]


def message_cell(kind, pid, t):
    keeps = pid == "P12K"
    title = ("message field the actor keeps in its state" if keeps
             else "message field the actor only reads (dropped with the message)")
    g = Gen("%s-%s-%s" % (kind.id, pid, t))
    if kind.id == "K9":
        return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
    if kind.id in ("K5", "K8"):
        need_doc(g)
    if t == "T2" and not keeps:
        return "an actor that drops the field has nothing to overwrite"
    if t == "T7" and keeps:
        return "a kept field passed to a keeper is P12D-T7 with the state besides"
    if t == "T7" and kind.zero is None:
        return NO_GLOBAL
    g.decl("message Put", "message Put {\n    v: %s\n}" % kind.ty)
    if t == "T2":
        arm = ["Put(v: x) -> {", "    v = x", "}"]
        check_tag = "b"
    else:
        arm = ["Put(v: x) -> {"] + block(kind.check(g, "x", "a", "the field the actor received"), 1)
        if keeps:
            arm += ["    v = x"]
        if t == "T7":
            helper_keep(g, kind)
            arm += ["    keep(x)"]
        arm += ["}"]
        check_tag = "a"
    check_body = kind.check(g, "v", check_tag, "the state, when asked") if keeps else []
    check_arm = ["Check() -> {"] + block(check_body, 1) + ["    reply Ack { n: 1 }", "}"]
    actor = ["actor Holder {"] + (["    " + STATE_DECL["K1" if kind.is_string else kind.id]] if keeps else []) + ["    receive {"] + \
        block(arm + check_arm, 2) + ["    }", "}"]
    pa, ea = kind.fresh(g, "a")
    if t in ("T1", "T7"):
        body = pa + ["h ! Put { v: %s }" % ea]
    elif t == "T2":
        pb, eb = kind.fresh(g, "b")
        body = pa + ["h ! Put { v: %s }" % ea] + pb + ["h ! Put { v: %s }" % eb]
    elif t == "T12":
        body = pa + [kind.bind_local("x", ea), "h ! Put { v: x }"] + \
            kind.check(g, "x", "a", "the sender's local, after the send")
    else:
        return None
    body += ["int n = h ? Check {}", 'check(n == 1, "the actor answered")']
    if t == "T7":
        body += kind.check(g, "kept", "a", "the field the actor kept in a module var, after the message was dropped")
    return actor_program(g, kind, (pid, title), t, actor,
                         shape_fn(None, body, params="w: string, k: int, h: ptr",
                                  comment="The shape: %s." % ("send a fresh value" if t in ("T1", "T7") else
                                                                 "send two values, the second replaces the first" if t == "T2"
                                                                 else "send a local, read it after the send")),
                         ["shape(w, k, h)"])


P12_TRANSFERS = ["T1", "T2", "T7", "T12"]


# ---- P14 / P15 / P16: a part of a parameter -------------------------------


def param_cell(kind, pid, t):
    g = Gen("%s-%s-%s" % (kind.id, pid, t))
    if kind.id == "K9":
        return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
    if pid == "P14":
        title = "field of a struct parameter"
        if kind.id in ("K5", "K8"):
            need_doc(g)
        g.decl("struct Box", "struct Box {\n    v: %s\n}" % kind.ty)
        ptype, place = "Box", "p.v"
        pa, ea = kind.fresh(g, "a")
        make = pa + ["h = Box { v: %s }" % ea]
        caller_read = "h.v"

        def caller_store(tag):
            pre, e = kind.fresh(g, tag)
            return pre + ["h = Box { v: %s }" % e]
    else:
        if kind.id in ("K4", "K7", "K8"):
            return "arrays are one-dimensional: an array cannot hold an array"
        if kind.id in ("K2", "K6"):
            return "an array of optionals or tuples is not measured (P5 covers the local)"
        title = ("element of a fixed-size array parameter" if pid == "P15"
                 else "element reached through a slice parameter")
        elem = kind.ty
        ptype = "%s[2]" % elem if pid == "P15" else "%s[]" % elem
        place = "p[0]"
        pa, ea = kind.fresh(g, "a")
        pz, ez = kind.fresh(g, "z")
        make = pa + pz + ["xs = [%s, %s]" % (ea, ez)]
        caller_read = "xs[0]"

        def caller_store(tag):
            pre, e = kind.fresh(g, tag)
            return pre + ["xs[0] = %s" % e]
    slice_param = pid == "P16"
    # The transfer, inside the callee.
    callee_ret = "int"
    caller_tag = "a"
    round_lines = ["shape(w, k)"]
    shape_ret = None
    pre_call = []
    if t == "T1":
        ops = kind.check(g, place, "a", "the parameter's part") + ["return 1"]
    elif t == "T2":
        pb, eb = kind.fresh(g, "b")
        ops = kind.check(g, place, "a", "the parameter's part") + pb + ["%s = %s" % (place, eb)] + \
            kind.check(g, place, "b", "the part, after the callee overwrote it") + ["return 1"]
        if slice_param:
            caller_tag = "b"
    elif t == "T4":
        ops = kind.check(g, place, "a", "the parameter's part") + \
            ["if k % 2 == 0 {", "    return 1", "}"] + kind.check(g, place, "a", "the part, late") + ["return 0"]
    elif t == "T5":
        ops = kind.check(g, place, "a", "the parameter's part") + ['panic("stop")', "return 0"]
    elif t == "T6":
        helper_reads(g, kind)
        ops = ["n = reads(%s)" % place, 'check(n == 1, "the reader ran")', "return n"]
    elif t in ("T7", "T7S"):
        if kind.zero is None:
            return NO_GLOBAL
        some = t == "T7S"
        helper_keep(g, kind, some)
        ops = ["keep_some(%s, k)" % place if some else "keep(%s)" % place, "return 1"]
        after = kind.check(g, "kept", "a", "the kept value, after the scope ended")
        round_lines = ["shape(w, k)"] + (["if k % 2 == 0 {"] + block(after, 1) + ["}"] if some else after)
    elif t in ("T8", "T8S"):
        if kind.id != "K1":
            return "only a string has a free a callee can call"
        some = t == "T8S"
        helper_frees(g, some)
        ops = ["frees_some(%s, k)" % place if some else "frees(%s)" % place, "return 1"]
    elif t in ("T9", "T10"):
        callee_ret = kind.ty
        r = place
        if t == "T10":
            helper_id(g, kind)
            r = "id(%s)" % place
        pc, ec = kind.fresh(g, "c")
        ops = ["if k % 2 == 0 {", "    return %s" % r, "}",
               "// The other path: the part is left, and a fresh value returned."] + pc + ["return %s" % ec]
    elif t == "T12":
        pb, eb = kind.fresh(g, "b")
        ops = [kind.bind_local("y", place)] + pb + ["%s = %s" % (place, eb)] + \
            kind.check(g, "y", "a", "the alias, after the part was overwritten") + \
            kind.check(g, place, "b", "the part, after the overwrite") + ["return 1"]
        if slice_param:
            caller_tag = "b"
    elif t == "T14":
        if kind.zero is None:
            return NO_GLOBAL
        helper_held(g, kind)
        ops = ["held = %s" % place, "return 1"]
        round_lines = ["shape(w, k)"] + kind.check(g, "held", "a", "the module var, after the scope ended")
    elif t == "T16":
        if slice_param:
            return "a slice is a view: a closure that captures it sees the stores made through it"
        helper_reads(g, kind)
        pb, eb = kind.fresh(g, "b")
        ops = ["f = || { return reads(%s) }" % place] + pb + ["%s = %s" % (place, eb)] + \
            ["int n = call(f)", 'check(n == 1, "the closure read its copy")', "return n"]
        if slice_param:
            caller_tag = "b"
    else:
        return None
    callee = ["// The callee: %s, on its parameter's part." % TRANSFER[t],
              "use(p: %s, w: string, k: int) -> %s {" % (ptype, callee_ret)] + block(ops, 1) + ["}"]
    g.decl("fn use", "\n".join(callee))
    if t in ("T9", "T10"):
        body = make + [kind.bind_local("v", "use(%s, w, k)" % ("h" if pid == "P14" else "xs"))] + \
            caller_store("b") + ["if k % 2 == 0 {"] + \
            block(kind.check(g, "v", "a", "the returned part, after the caller overwrote its own"), 1) + \
            ["} else {"] + block(kind.check(g, "v", "c", "the value the other path returned"), 1) + ["}"]
    elif t == "T5":
        arg = "h" if pid == "P14" else "xs"
        body = make + ["try {", "    use(%s, w, k)" % arg] + catch_lines() + \
            kind.check(g, caller_read, "a", "the caller's value, after the callee panicked")
    else:
        arg = "h" if pid == "P14" else "xs"
        body = make + ["n = use(%s, w, k)" % arg]
        if caller_tag:
            body += kind.check(g, caller_read, caller_tag, "the caller's value, after the call")
    return program(g, kind, (pid, title), t, shape_fn(shape_ret, body, comment="The caller."), round_lines)


PARAM_TRANSFERS = ["T1", "T2", "T4", "T5", "T6", "T7", "T7S", "T8", "T8S", "T9", "T10", "T12", "T14", "T16"]


# ---- P17: a temporary -----------------------------------------------------


def temp_cell(kind, t):
    pid, title = "P17", "temporary (a call argument or a value never bound)"
    g = Gen("%s-%s-%s" % (kind.id, pid, t))
    if kind.id == "K9":
        return "K9 is covered in a struct `fn` field, a ptr slot and a container only"
    pa, ea = kind.fresh(g, "a")
    round_lines = ["shape(w, k)"]
    ret = None
    if t == "T1":
        body = pa + ["_ = %s" % ea]
    elif t == "T5":
        helper_boom(g, kind)
        body = ["try {"] + block(pa + ["n = boom(%s, k)" % ea], 1) + catch_lines()
    elif t == "T6":
        helper_reads(g, kind)
        body = pa + ["n = reads(%s)" % ea, 'check(n == 1, "the reader ran")']
    elif t in ("T7", "T7S"):
        if kind.zero is None:
            return NO_GLOBAL
        some = t == "T7S"
        helper_keep(g, kind, some)
        body = pa + ["keep_some(%s, k)" % ea if some else "keep(%s)" % ea]
        after = kind.check(g, "kept", "a", "the kept value, after the call")
        round_lines = ["shape(w, k)"] + (["if k % 2 == 0 {"] + block(after, 1) + ["}"] if some else after)
    elif t in ("T8", "T8S"):
        if kind.id != "K1":
            return "only a string has a free a callee can call"
        some = t == "T8S"
        helper_frees(g, some)
        body = pa + ["frees_some(%s, k)" % ea if some else "frees(%s)" % ea]
    elif t in ("T9", "T10"):
        ret = kind.ty
        if t == "T10":
            helper_id(g, kind)
            body = pa + ["return id(%s)" % ea]
        else:
            body = pa + ["return %s" % ea]
        round_lines = [kind.bind_local("v", "shape(w, k)")] + kind.check(g, "v", "a", "the returned value")
    else:
        return None
    return program(g, kind, (pid, title), t, shape_fn(ret, body, comment="The shape: %s." % TRANSFER[t]),
                   round_lines)


P17_TRANSFERS = ["T1", "T5", "T6", "T7", "T7S", "T8", "T8S", "T9", "T10"]


# ---- KE: the error string of a `T!` result ----------------------------------


def error_cells():
    """The fallible-result cells of the PR's tuple comment: a heap error in
    the error slot of an `int!`, through `x!`, `or`, a destructure and a
    pass-through."""
    out = []
    fails = ("// Fails with a fresh error string.\n"
             "fails(w: string) -> int! {\n"
             "    return 0, string.concat(w, \"#a\")\n"
             "}")

    def mk(place, t, title, decls, shape, round_lines, note):
        g = Gen("KE-%s-%s" % (place[0], t))
        g.decl("fn fails", fails)
        for k, v in decls:
            g.decl(k, v)

        class KE(Kind):
            id, title = "KE", "fresh error string in the error slot of an `int!` result"
        src = program(g, KE(), place, t, shape, round_lines, note=note)
        out.append(Cell("KE", place[0], t, src, note=title))

    P1t = ("P1", "locals bound by a destructure")
    P17t = ("P17", "temporary (the result never bound)")
    mk(P1t, "T1", "destructured into locals, then left",
       [], shape_fn(None, ["n, e = fails(w)", 'check(n == 0 && e == "w#a", "the error slot")']),
       ["shape(w, k)"], "")
    mk(P17t, "T5", "`x!` outside a `T!` function panics with the error; `try` catches it",
       [], shape_fn(None, ["try {", "    n = fails(w)!", "    check(n == 1, \"not reached\")"] + catch_lines()[:1] +
                    ['    check(e == "w#a", "the panic carries the error")', "}"]),
       ["shape(w, k)"], "The panic reason is the heap error string (PR #2883, tuples comment).")
    mk(P17t, "T6", "an `or { }` handler reads `err`",
       [], shape_fn(None, ["n = fails(w) or {", '    check(err == "w#a", "the error in the handler")', "    -1",
                           "}", 'check(n == -1, "the handler\'s value")']),
       ["shape(w, k)"], "")
    mk(P17t, "T9", "propagated by `x!` inside a `T!` function",
       [("fn relay", "// Propagates the error with `!`.\nrelay(w: string) -> int! {\n    n = fails(w)!\n    return n + 1\n}")],
       shape_fn(None, ["n, e = relay(w)", 'check(e == "w#a", "the propagated error")']),
       ["shape(w, k)"], "")
    mk(P17t, "T10", "passed through whole (`return fails(w)`)",
       [("fn pass", "// Passes the whole result through.\npass(w: string) -> int! {\n    return fails(w)\n}")],
       shape_fn(None, ["n, e = pass(w)", 'check(e == "w#a", "the passed-through error")']),
       ["shape(w, k)"], "")
    mk(P17t, "T10M", "a `T!` function returns an extern's literal error on one path and its own heap error on the other",
       [("extern open", "extern io_fd_open_read_tuple(path: string) -> (int, string)"),
        ("fn mixed", "// Passes a C function's result through on odd calls (its error is a\n"
         "// literal), and fails with a fresh error of its own on even calls.\n"
         "mixed(w: string, k: int) -> int! {\n"
         "    if k % 2 == 1 {\n"
         "        return io_fd_open_read_tuple(\"/nonexistent/ownership-grid\")\n"
         "    }\n"
         "    return 0, string.concat(w, \"#a\")\n"
         "}")],
       shape_fn(None, ["n, e = mixed(w, k)", "if k % 2 == 0 {", '    check(e == "w#a", "the function\'s own error")',
                       "} else {", '    check(e != "", "the extern\'s error")', "}"]),
       ["shape(w, k)"], "PR #2883 (tuples comment): the pass-through vetoes the error position.")
    mk(P17t, "T9M", "`x!` propagates an operand's heap error inside a function whose error position is vetoed",
       [("extern open", "extern io_fd_open_read_tuple(path: string) -> (int, string)"),
        ("fn vetoed", "// One return passes a C function's result through (vetoing the error\n"
         "// position); the other propagates fails()'s heap error with `!`.\n"
         "vetoed(w: string, k: int) -> int! {\n"
         "    if k % 2 == 1 {\n"
         "        return io_fd_open_read_tuple(\"/nonexistent/ownership-grid\")\n"
         "    }\n"
         "    n = fails(w)!\n"
         "    return n\n"
         "}")],
       shape_fn(None, ["n, e = vetoed(w, k)", "if k % 2 == 0 {", '    check(e == "w#a", "the propagated error")',
                       "} else {", '    check(e != "", "the extern\'s error")', "}"]),
       ["shape(w, k)"], "PR #2883 (tuples comment): the propagated operand's error leaks.")
    for c in out:
        c.kind_title = "fresh error string in the error slot of an `int!` result"
    return out


# ---------------------------------------------------------------------------

PLACES = [
    ("P1", "local"),
    ("P2", "local rebound in a loop body"),
    ("P3", "local bound only in the branches of an if/else"),
    ("P3B", "local bound and used inside one branch of an if"),
    ("P3E", "local bound and used inside each branch of an if/else"),
    ("P4", "field of a local struct"),
    ("P5", "element of a fixed-size array local"),
    ("P5L", "element of a fixed-size array local rebound in a loop body"),
    ("P6", "slot of a tuple local"),
    ("P7", "optional payload"),
    ("P8", "module `var`"),
    ("P9", "captured by a closure that reads it (a copy)"),
    ("P9W", "captured by a closure that rebinds it (a shared cell)"),
    ("P10L", "element of a `std.list`"),
    ("P10M", "value of a `std.map`"),
    ("P11", "actor state"),
    ("P12K", "message field the actor keeps"),
    ("P12D", "message field the actor drops"),
    ("P13G", "module `ptr` var holding a closure"),
    ("P13D", "module `ptr` var assigned a closure bare"),
    ("P13F", "`ptr` field of a local struct holding a closure"),
    ("P14", "field of a struct parameter"),
    ("P15", "element of a fixed-size array parameter"),
    ("P16", "element reached through a slice parameter"),
    ("P17", "temporary (never bound)"),
    ("P18", "string field of an element of a struct array local"),
]
PLACE_TITLE = dict(PLACES)

_cells = None
_skips = None
PRODUCER_NOT_CROSSED = 0


def _build():
    global _cells, _skips
    cells, skips = [], []
    global PRODUCER_NOT_CROSSED
    PRODUCER_NOT_CROSSED = 0
    for kind in KINDS:
        for pid, _ in PLACES:
            for t, _ in TRANSFERS:
                if isinstance(kind, Producer) and (pid not in PRODUCER_PLACES or t not in PRODUCER_TRANSFERS):
                    PRODUCER_NOT_CROSSED += 1
                    continue
                res = None
                if pid in ("P9", "P9W"):
                    res = captured_cell(kind, pid, t) if t in P9_TRANSFERS else "not a transfer of a captured value"
                elif pid == "P11":
                    res = state_cell(kind, t) if t in P11_TRANSFERS else (
                        "the state outlives every arm: no scope of its own to leave" if t in ("T3", "T4", "T5", "T11", "T11R")
                        else "not a transfer of actor state")
                elif pid in ("P12K", "P12D"):
                    res = message_cell(kind, pid, t) if t in P12_TRANSFERS else "a message field is sent: store, overwrite or send a local"
                elif pid in ("P14", "P15", "P16"):
                    res = param_cell(kind, pid, t) if t in PARAM_TRANSFERS else "not a transfer of a parameter's part"
                elif pid == "P17":
                    res = temp_cell(kind, t) if t in P17_TRANSFERS else "a temporary is never stored, overwritten or aliased"
                else:
                    place = next(p for p in SIMPLE if p.id == pid)
                    res = simple_cell(kind, place, t)
                if res is None:
                    res = "not meaningful"
                if res.startswith("// Ownership grid cell"):
                    cells.append(Cell(kind.id, pid, t, res))
                else:
                    skips.append(Skip(kind.id, pid, t, res))
    cells += error_cells()
    _cells, _skips = cells, skips


def cells():
    if _cells is None:
        _build()
    return _cells


def skipped():
    if _skips is None:
        _build()
    return _skips


def kind_title(kid):
    if kid == "KE":
        return "fresh error string in the error slot of an `int!` result"
    return KIND[kid].title


def is_producer(kid):
    return isinstance(KIND.get(kid), Producer)


def main(argv):
    if "--list" in argv:
        for c in cells():
            print(c.id)
        print("%d cells" % len(cells()), file=sys.stderr)
        return 0
    if "--skips" in argv:
        for s in skipped():
            print("%s-%s-%s: %s" % (s.kind, s.place, s.transfer, s.reason))
        return 0
    if "--show" in argv:
        want = argv[argv.index("--show") + 1]
        for c in cells():
            if c.id == want:
                sys.stdout.write(c.source)
                return 0
        print("no cell " + want, file=sys.stderr)
        return 1
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
