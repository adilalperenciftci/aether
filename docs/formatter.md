# `ae fmt`, the source formatter

`ae fmt` rewrites Aether source into a canonical layout: consistent 4-space
indentation, normalized spacing around operators and punctuation, at most one
blank line between constructs, no trailing whitespace, and a single final
newline. Run it before committing, or wire it into an editor-save hook or CI
check.

## Usage

```bash
ae fmt                    # read stdin, write formatted source to stdout
ae fmt path/to/file.ae    # format one file in place
ae fmt src tests          # format every .ae file under these directories, in place
ae fmt --check src        # do not write; list files that would change, exit 1 if any do
```

- With **no path**, it reads standard input and writes the formatted result to
  standard output (useful for editor "format buffer" integrations).
- With **paths**, it formats each `.ae` file in place, recursing into
  directories and skipping hidden ones (`.git`, `.aether`, ...). It prints the
  path of every file it rewrites.
- `--check` (alias `-c`) writes nothing and exits non-zero if any file is not
  already formatted, listing those files. Use it in CI to enforce formatting.

Writes are atomic (a temp file is renamed over the original), so an interrupted
run never leaves a half-written file.

Line endings are LF in the output: a CRLF file (a Windows checkout with
`core.autocrlf`) is reported by `--check` and rewritten to LF, which is what
this repository's `.gitattributes` pins for `*.ae` anyway. The compiler
accepts either.

A UTF-8 byte order mark starting the file is kept where it is: it is no part
of the program's text (see [Source Files](language-reference.md#source-files)),
and the formatter changes whitespace only.

## What it does, and does not, change

The formatter is deliberately conservative: it changes **only whitespace**.

It normalizes:

- **Indentation**, by brace/bracket/paren nesting (4 spaces per level).
- **Inter-token spacing**: one space around binary operators and after `,`/`:`;
  none before `,`/`;`/`:`, none inside `(`/`[` at their edges, one space before
  a `{`. Struct and message literals read `Name { field: value }`. The type
  prefixes are written tight: `make([]int, n)`, `make([]*Node, n)`,
  `[Dir]string`; an index keeps its space before a word (`a[0] as int`). An
  index is written tight to the value it indexes (`xs[0]`, `f()[1]`), and an
  array type's size to its element type (`fn[2]`), while an array literal after
  a keyword keeps its space (`return []`, `for x in [1, 2]`). A prefix
  operator is written tight to its operand (`-x`, `*p`), and an operator that
  begins a line is always a prefix one, since an expression never continues
  with an operator on a new line (`-2` as a block's last value). A postfix `!`
  ends a value (`f()! + g()!`), and `or` after a value keeps its space before
  a parenthesis (`x or (y or { 1 })`), which is its handler, not a call.
  What follows a type's optional suffix is spaced as it would be after the
  type, so a closure's parameters read `| o: int? |` as they read
  `| s: Shape |`; elsewhere the spacing around a `?` (an actor ask) and a `!`
  is the author's.
- **Blank lines**: runs of blank lines collapse to at most one, and a blank line
  is never left immediately after `{` or before `}`.
- **Trailing whitespace** is stripped; the file ends in exactly one newline.

It preserves, byte for byte:

- **Your line breaks.** The formatter re-indents and re-spaces but does not
  reflow expressions onto different lines. Where you break a long call or list
  is left to you.
- **Comments**, including inline `//` and multi-line `/* ... */`.
- **String literals** and their `${...}` interpolation, **heredocs**
  (`<<MARKER ... MARKER`, whose body indentation is significant), and **backtick
  raw identifiers** (`` `reply` ``).

## Short names: `--short-names`

```bash
ae fmt --short-names src tests   # json.json_free(v) -> json.free(v), where both are one function
```

A call that names its module twice, `json.json_free(v)`, reaches the same
function as `json.free(v)`. With `--short-names`, `ae fmt` rewrites such calls
to the short form, and changes nothing else: not the layout, and not a call
whose short form is another declaration. Which calls qualify is the
compiler's answer, not a pattern: `aetherc --emit=short-names` checks the file
and lists each call written `ns.ns_x(...)` whose `ns.x` resolves to the same
declaration. A module may not export two names that answer to one short name
(E0305, [module-system-design.md](module-system-design.md)), so a module's
long name and its short form are one declaration; a name whose short form
would start with a digit (`sha3.sha3_256_hex`) is left as written. A file
that does not compile is reported and left as it is. `ae check` warns on each
call this would rewrite (W1006), naming this command, so the long form does
not come back. With `--check`, it lists the files it
would rewrite and exits 1 if there are any.

The rewrite does not change what a program compiles to: the C it generates is
byte-identical before and after (modulo `#line` directives), which is how the
tree's own calls were rewritten (#2976).

## Safety guarantee

`ae fmt` cannot change what your program does. It works on the token stream: the
sequence of significant tokens is never reordered, dropped, or fused, and string
and comment bytes are copied verbatim. Because the lexer already tokenizes `a-b`
and `a - b` identically, re-spacing between separated tokens cannot change how
the source parses; the one hazard, gluing two tokens that would re-lex as one
(`a b` becoming `ab`, or `<` `<` becoming `<<`), is explicitly prevented.

This is verified, not only asserted: formatting every program in `examples/` and
`tests/` produces byte-identical generated C (modulo `#line` directives), and
formatting is idempotent (`fmt(fmt(x)) == fmt(x)`) across the whole corpus.

Both properties are enforced in CI:
`tests/integration/fmt_gate/test_fmt_gate.sh` fails the build if any
checked-in `.ae` file under `std/`, `examples/`, or `tests/` is not
canonically formatted (`ae fmt --check`), if formatting stops being
idempotent, or if a formatted file's generated C diverges from the
original's (modulo `#line`). Run `ae fmt std examples tests` before
committing to stay canonical.

## Not yet done

The formatter does not reflow long lines or align consecutive declarations. Those
are layout decisions that need an opinionated style pass; they can be added later
without changing the safety model above.
