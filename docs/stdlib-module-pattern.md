# Aether Stdlib Module Pattern

This is the canonical shape for an Aether standard-library module. Use it
when adding a new `std/<name>/` module or retrofitting an existing one.

The worked example throughout this document is
[`std/fs/module.ae`](../std/fs/module.ae), read it alongside this doc.

## The shape

Every `std/<name>/module.ae` has two layers:

1. **Raw externs**, thin declarations of the underlying C functions.
   Fallible externs use a `_raw` suffix and return the old C conventions
   (`ptr` for nullable, `int` for 1/0 success flags).
2. **Go-style wrappers**, Aether functions that call the raw externs
   and translate C-style returns into Go-style `(value, err)` tuples
   (or just `err` for operations with no return value).

```
// std.X - ... header
//
// API shape:
//   - Raw externs end in `_raw` and return ptr/int in the old C-style
//     convention. They are the escape hatch for advanced callers.
//   - Aether-native wrappers (below) use Go-style `(value, err)` tuple
//     returns and are the idiomatic way to call X operations.

// ---- raw externs ----
extern X_op_raw(args) -> ptr
extern X_pure_op(args) -> int     // infallible, no _raw, no wrapper

// ---- Go-style wrappers ----
// Short docstring stating: what it does, and exactly what shape it
// returns on success vs. failure.
op(args) -> {
    r = X_op_raw(args)
    if r == null {
        return null, "human-readable error"
    }
    return r, ""
}
```

## Rules

### When to add a `_raw` extern + wrapper

Any operation that can **fail at runtime**, open a file that doesn't
exist, allocate when memory is tight, parse malformed input, look up an
absent key, etc. These get:

- A `_raw`-suffixed C function (either rename the existing one or add
  it alongside).
- A companion Aether wrapper that turns the C return into either
  `(value, "")` on success or `(zero-value, "reason")` on failure.

### When NOT to wrap

Keep raw externs with **no** `_raw` suffix and **no** wrapper for
operations that are:

- Pure total functions that can't fail for any well-typed input
  (`math_sqrt`, `math_sin`, `string_length`, `list_size`), and
  infallible boolean queries (`file_exists`, `fs_is_symlink`,
  `json_is_null`, `map_has`).
- **Sentinel-returning infallibles** where the sentinel is part of the
  contract, not an error. Example: `file_mtime` returns `0` for missing
  files or stat failure, callers already handle zero as "no mtime", so
  wrapping would only add noise.
- **Intentionally void fire-and-forget operations.** Example:
  [`log_write`](../std/log/module.ae) in `std.log` the module
  deliberately degrades to stderr if the log file is unopenable, so
  callers don't need an error from each write.
- **Structural/DSL builders.** Example: the manifest DSL in
  [`std.host`](../std/host/module.ae), `describe`, `input`, `event`,
  `bindings`, `java`, … are void because they structurally append to a
  global registry. They're not silent failures, they're a different
  pattern.

### One name per operation, and the short one at call sites

A module's extern is spelt with the module's prefix (`json_free`) because
that is its C name, but a caller reaches it by its short name: `json.free(v)`
resolves to the extern `json_free`, as `md5.hex` resolves to std.md5's Aether
function `md5_hex` (a module's names are looked up as written, then in the
prefixed form, #2976). Write calls, examples and READMEs with the short name;
`json.json_free(v)` names the module twice for the same function, `ae check`
warns on it (W1006), and `ae fmt --short-names` rewrites such calls where the
compiler resolves both spellings to one declaration.

A module exports one name per operation. Two exports that answer to one
short name, a wrapper `x` beside its extern `<module>_x` or
`aether_<module>_x`, are an error (E0305, naming both): `module.x` would
reach one and `module.<module>_x` the other, the same operation twice, or,
worse, a different one that reads as the same. A wrapper's extern is
declared for the wrapper to call and left out of `exports(...)`. An extern
that callers need beside a wrapper, because it does something the wrapper
does not, gets a name that says it is raw, as the `_raw` externs above do:

```
exports(add, add_raw)
@extern("aether_set_add") add_raw(set: ptr, item: string) -> int
add(set: ptr, item: string) -> bool { return add_raw(set, item) == 1 }
```

std dropped 336 such duplicate exports from its lists (#2976); the
changelog names each one.

The rule is one name per operation, which E0305 checks only where the two
names share a short name. An alias under another name is the same
duplicate: `json.from_int` beside the extern `json.create_int`, or
`xml.writer` beside `xml.builder_new`. Export the Aether-side name, the
short one a caller reads, unless the other spelling says more (std.cbor's
`map_push` appends a pair where `map_set` would suggest a replace), and
keep the extern for the wrapper to call. std dropped 79 such aliases
(#3014).

### Return shapes

| Operation | Success return | Failure return |
|---|---|---|
| Produces a value | `(value, "")` | `(zero-value, "reason")` |
| Produces nothing (setter, writer) | `""` | `"reason"` |
| Lookup that can be absent | `(value, "")` / `(null, "")` for absent | `(null, "reason")` for error |

For the lookup row: distinguish **absent** from **error**. An absent key
is not an error, the caller asked if X exists. Only return a non-empty
error string when something actually went wrong (null receiver, wrong
type, allocation failure).

### Structured errors (pilot)

A small set of newer wrappers extends the (value, err) shape with a
**third element**: an integer "kind" that lets callers
programmatically discriminate between failure modes without parsing
the human-readable message. The tuple is `(value, kind: int,
message: string)`. `kind == 0` means success (constant `KIND_OK`);
non-zero means an error of the named class.

```
// (bytes_copied, kind, message)
//   on success:  (n, KIND_OK, "")
//   on failure:  (bytes_so_far, KIND_NOT_FOUND, "open src: ...")
copy(src: string, dst: string) -> (int, int, string) {
    return fs_copy_raw(src, dst)
}
```

Why kinds are returned per-call (not via process-global accessors like
`vcr.last_kind()`): std.fs is called concurrently from actors; a
shared mutable slot would race. The triple costs one extra register
on every ABI we target (x86-64 SysV, AArch64 AAPCS, MS x64).

The kinds themselves are exported `const int` values from the module
that uses them (e.g. `fs.KIND_NOT_FOUND`, `fs.KIND_PERMISSION_DENIED`).
Modules that use kinds **must** also export a matching
`AETHER_<MODULE>_KIND_*` C macro set in their header so the C side
and the Aether surface stay in lock-step.

This shape is **opt-in and additive**. Existing wrappers keep their
(value, err) or string-error returns, converting them is a
non-breaking but wider change tracked separately. The pilot scope is
`std.fs.{copy, move, realpath, chmod}`. Future modules may adopt the
shape after the pilot has shaken out.

| Operation | Success return | Failure return |
|---|---|---|
| Structured-error producer | `(value, KIND_OK, "")` | `(zero-value-or-partial, KIND_*, "reason")` |

### std is silent

A program built on std, or a library built with `--emit=lib` and loaded by a
JVM, CPython or Node, finds nothing on its stdout or stderr that it did not put
there. A module reports through the channels a program can act on:

1. **Failures travel in the return value**, with the specific reason in the
   error string: `"cannot bind 0.0.0.0:8080: Address already in use"`, not
   `"bind failed"`. A raw extern that returns a bare `-1` leaves its reason
   where an accessor can read it (`http_server_error(server)`).
2. **State is readable through accessors**, as `http_server_port()` and
   `request_remote_addr()` are.
3. **A long-lived component offers a monitor.** A component with a lifecycle
   (create, configure, start, stop), such as the HTTP server, calls closures
   the program registers while configuring it, one per event and each with
   typed arguments. The module ships its stock monitors beside it: one that
   writes to the console, and one that says nothing. A default may be the
   console one where a human is plainly watching: the HTTP server gives a
   foreground server (`server_start`) the console monitor and an embedded one
   (`server_start_background`) none, unless the program chose.

    ```aether,fragment
    srv = http.server_create(8080)
    http.monitor(srv) {
        listening() |host: string, port: int| { println("up on ${host}:${port}") }
        stopped() |host: string, port: int| { flush_metrics() }
    }
    err = http.server_start(srv)
    ```

Exempt:

- modules whose output is the product: `std.io`, `std.log`, `std.spec`, a CLI
  parser's help text;
- output the program explicitly asked for (`std.tracking`'s leak report);
- one last line before `abort()` or a panic, where no caller is left to return
  to.

`make check-docs` runs `tests/scripts/check_std_silent.py`, which fails on a
write to stdout or stderr from the C under `std/` (`std.io`, `std.log` and
vendored sources aside). An exempt write carries `silent-ok: <why>` on its line
or the comment line above it, so a new one needs a reason a reviewer can read.
A stock monitor is ordinary Aether in the module's `module.ae`, which the gate
does not read: the program chose it, or the module's documented default did.

### Docstring

Every wrapper gets a short docstring stating what it does and **the
exact return shape**. Match this voice:

```
// Open a file. Returns (handle, "") on success, (null, error) on failure.
open(path: string, mode: string) -> {
    ...
}
```

### Ownership of returned strings

Declare each extern's string result by what C hands over (R4 of the
[ownership rules](memory-management.md#c-boundaries-r4)): `-> string @heap`
when C returns a string the caller owns, which the call adopts with no
copy, and plain `-> string` when C returns a pointer into memory it keeps.
A wrapper that returns a borrowed result needs no copy of its own: a
`return` hands the caller one reference, and a plain C string is copied
into a counted one there, so the caller's string outlives the source object.

## Worked example: `std.fs`

[`std/fs/module.ae`](../std/fs/module.ae) is the reference
implementation. Skim it start-to-finish; it demonstrates:

- Raw `_raw` externs grouped at the top with structural comments.
- Pure-function externs (the `path_*` block) that correctly have no
  `_raw` suffix and no wrapper.
- Every fallible operation wrapped in a Go-style function below.
- Consistent `"cannot <verb> <noun>"` error phrasing.
- An explicit note where a raw extern is left unwrapped intentionally
  (`file_mtime`'s sentinel-0 contract).

## Modules that follow this pattern

`fs`, `io`, `http`, `net`, `os`, `string`, `tcp`, `dir`, `file` full
wrapper coverage. `json`, `collections`, `list`, `map` completed in
the stdlib-consistency pass alongside this doc. `log` and `host`,
intentionally follow domain-specific variants (fire-and-forget logging;
DSL builders) as described above.

## Adding a new stdlib module

1. Create `std/<name>/` with `module.ae` and `aether_<name>.c`/`.h`.
2. Write the C functions first; split into `<op>_raw` (fallible) and
   `<op>` (infallible) per the rules above.
3. Mirror each function as an `extern` in `module.ae`, copying the
   `_raw` suffix for fallible ones.
4. Add the "API shape" preamble comment.
5. Add Go-style wrappers for every fallible extern.
6. Add tests exercising both the success and error paths of each
   wrapper, as a co-located `std/<name>/test_<name>.ae` (#1584): the
   sweep runs it, the install strips it, and `make check-tests` fails a
   module that has no test anywhere.
7. Add an example under `examples/03-std/` showing idiomatic use of
   the Go-style API, in the format examples/README.md describes (what it
   teaches, how to run it, the output it prints), and its row in that
   README.
