# Aether examples

A path through Aether, from the first program to actors, servers and C.
Read them in order: each file teaches one idea, starts by saying what it
teaches and how to run it, and ends with the exact output it prints. CI
runs every example that can run and fails when one stops printing what
it says (`make check-examples`).

Run them from the repository root:

```sh
ae run examples/01-language/01-hello.ae
```

With a toolchain built from this tree, that is `./build/ae run ...`. The
[language reference](../docs/language-reference.md) is the full story
behind each step; every row below links the part it builds on.

## 1. The language

| Example | What it teaches | Reference |
|---|---|---|
| [01-hello.ae](01-language/01-hello.ae) | `main`, `println`, interpolation | [Functions](../docs/language-reference.md#functions) |
| [02-values-and-types.ae](01-language/02-values-and-types.ae) | numbers, bools, strings, written types, `const`, module `var`, `as` | [Types](../docs/language-reference.md#types) |
| [03-strings.ae](01-language/03-strings.ae) | escapes, comparison by content, std.string, parsing numbers | [String literals](../docs/language-reference.md#string-literals) |
| [04-control-flow.ae](01-language/04-control-flow.ae) | `if` as a statement and a value, `while`, `for`, `break`, labels | [Control flow](../docs/language-reference.md#control-flow) |
| [05-functions.ae](01-language/05-functions.ae) | typed parameters, defaults, named arguments, several results, clauses with guards | [Functions](../docs/language-reference.md#functions) |
| [06-structs.ae](01-language/06-structs.ae) | struct values, `&p` pointers, struct patterns, `@derive(eq)`, `using` | [Structs](../docs/language-reference.md#structs) |
| [07-enums-and-sums.ae](01-language/07-enums-and-sums.ae) | `enum`, sum types, exhaustive `match` | [Sum types](../docs/language-reference.md#sum--variant-types) |
| [08-match.ae](01-language/08-match.ae) | literals, ranges, strings, list and struct patterns | [Match expressions](../docs/language-reference.md#match-expressions) |
| [09-optionals.ae](01-language/09-optionals.ae) | `T?`, `none`, `??`, `?.`, narrowing | [Optionals](../docs/language-reference.md#optionals) |
| [10-errors.ae](01-language/10-errors.ae) | `(value, err)`, `T!`, `or`, `!`, `panic` and `try` | [Result types](../docs/language-reference.md#the-t-result-type-and-or--sugar) |
| [11-arrays-and-slices.ae](01-language/11-arrays-and-slices.ae) | fixed arrays, slices, `.len`, checked indexes, `make` | [Slices](../docs/language-reference.md#slices-t) |
| [12-collections.ae](01-language/12-collections.ae) | std.list, std.map, std.set, sorting | [Handles](../docs/memory-management.md#handles-and-defer) |
| [13-closures.ae](01-language/13-closures.ae) | closures, captured variables, `fn` parameters, trailing blocks | [Closures](../docs/closures-and-builder-dsl.md) |
| [14-modules/main.ae](01-language/14-modules/main.ae) | a module of your own, `exports`, `import ... as` | [Modules](../docs/language-reference.md#modules-and-imports) |
| [15-contracts.ae](01-language/15-contracts.ae) | `requires`, `ensures`, `where` | [Contracts](../docs/language-reference.md#function-contracts-requires--ensures) |
| [16-defer.ae](01-language/16-defer.ae) | `defer`, `defer try`, `defer catch` | [Defer](../docs/language-reference.md#defer-statement) |
| [17-ownership.ae](01-language/17-ownership.ae) | what the compiler frees, what the program frees | [Memory management](../docs/memory-management.md) |

## Writing an example

An example is one `.ae` file, or a directory when it needs more than one
(a module, a C file). Its header comment says what it teaches and holds:

- `// Run: <command>`, the command a reader types from the repository
  root: `ae run <file> [-- args]`, another `ae` command, or `sh <script>`.
- `// Needs: <what>`, when it cannot run unattended: a server that waits
  for requests, a terminal, a platform, a library. CI builds it.
- `// See: <doc>`, the part of the documentation it builds on.

A file that belongs to another example (a module it imports) says
`// Part of: <that example's file>` instead of `Run:`. An example that
runs unattended ends with its output, exactly:

```aether,fragment
// Output:
// Hello, Aether!
```

`make check-examples` builds every example (a warning fails it), runs the
ones with an `Output:` block and compares, and checks that this README
links every example and nothing else. Add the new example's row here, in
the place a reader should meet it. The checker is
[tests/examples/check.ae](../tests/examples/check.ae).
