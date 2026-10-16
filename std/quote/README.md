# std.quote

The tree a `quote` trailing block hands to a function. The language side
(the syntax, what a quote may contain, the errors, how captures work) is
[docs/quote.md](../../docs/quote.md); this page is the library you read the
tree with.

A function that wants a quote takes a `quote.Tree` as its last parameter.
The compiler type-checks the block as Aether and, instead of compiling it to
run, builds this tree and passes it:

```aether,run
import std.quote

// A library function: it receives the block as a tree, not a closure.
show(t: quote.Tree) {
    defer quote.free(t)
    println(quote.to_source(t))
    println(quote.dump(t))
}

main() {
    scale = 2.0
    show() quote | x: float | -> x * scale + 1.0
}
```
```output
| x: float | {
    return x * scale + 1.0
}
(param x :float) (capture scale :float) (BLOCK (RETURN :float (BINARY + :float (BINARY * :float (LOCAL x :float) (CAPTURE scale :float)) (LIT 1.0 :float))))
```

## The tree

`Tree`, `Node` and `Capture` are opaque handles; the accessors and the node
kinds are the contract.

| On a `Tree` | |
|---|---|
| `body(t)` | the body, a `BLOCK` node |
| `param_count(t)`, `param_name(t, i)`, `param_type(t, i)` | the parameters, `\| a: T, ... \|` |
| `capture_count(t)`, `capture(t, i)`, `capture_named(t, n)` | the outer variables the block reads |
| `helper_count(t)`, `helper(t, i)`, `helper_named(t, n)` | the `@quotable` functions the body reaches, callees first, each a `Tree` (version 2) |
| `function_name(t)`, `return_type(t)` | a helper's name and return type (`""` for a quote's own tree); a module's helper is named by the module's full path and the function (`ae3d_shaders_sky_oct_decode`), the same in every program |
| `source(t)` | `"file.ae:line"` of the quote |
| `hash(t)` | a hash of the tree's shape, the same in every build, for caching what a back end makes |
| `version(t)` | the format version it was built with (`quote.VERSION`) |
| `free(t)` | release the tree and its hold on the captured variables |

| On a `Node` | |
|---|---|
| `kind(n)` | one of the kinds below; `kind_name(k)` spells it |
| `type_of(n)` | the type the checker gave it, as Aether spells it: `"float"` (a C double), `"f32"` (a 32-bit float, the type of a lane such as `uv.x`), `"vec2"`, a struct's name; `""` on a statement |
| `name(n)` | a local's, parameter's or capture's name; a called function's (`"math.sin"`); a field's (`FIELD`, `FIELD_VALUE`) |
| `op(n)` | an operator: `"+"`, `"<"`, `"!"`; on `ASSIGN`, `"="`, `"+="`, ... |
| `lit(n)` | a literal's text |
| `child_count(n)`, `child(n, i)` | its children |
| `children(n)` | its children as a `std.list` of Node handles; free the list with `list.free` |
| `walk(n, f)` | call the closure `f` with `n` and every node under it, in pre-order |
| `line(n)` | its source line |

Kinds, version 2 (they are added, never removed or renumbered, and
`VERSION` goes up by one with each addition):

| Kind | Children |
|---|---|
| `BLOCK` | statements |
| `LET` | value: a new local, `name` and `type` |
| `ASSIGN` | target, value; `op` is `=`, `+=`, ... (`i++` is `i += 1`) |
| `RETURN` | value, or none |
| `IF` | cond, then, else? (an `else if` is an `IF` as the else) |
| `WHILE` | cond, body |
| `FOR` | init, cond, step, body |
| `BREAK`, `CONTINUE` | |
| `EXPR` | an expression statement |
| `LIT` | `lit` is the text; `type` says which |
| `LOCAL` | a local or a parameter, by `name` |
| `CAPTURE` | an outer variable, by `name` |
| `UNARY` | operand; `op` is `-`, `!` or `~` |
| `BINARY` | left, right |
| `CHOOSE` | cond, then, else: `if` used as a value |
| `CALL` | arguments; `name` is the function as written |
| `FIELD` | object; `name` is the field |
| `INDEX` | object, index |
| `MAKE` | a `FIELD_VALUE` per field; `type` is the struct |
| `FIELD_VALUE` | value; `name` is the field it sets |
| `HELPER_CALL` | arguments; `name` is a `@quotable` function the tree carries (version 2) |

## Freeing

Each evaluation of a quote builds a new tree, owned by the function it is
handed to: free it with `quote.free(t)` when done, `defer quote.free(t)`
being the idiom. A function that keeps the tree (in a struct, or by
returning it) hands the duty on with it. Trees are not freed at scope exit
([docs/quote.md](../../docs/quote.md#freeing-a-tree) says why).

## Walking a tree

`walk` visits a node and everything under it, a node before its children,
which is how a back end collects what it needs without a recursive function
of its own:

```aether,run
import std.quote

calls(t: quote.Tree) -> string {
    defer quote.free(t)
    seen = ""
    quote.walk(quote.body(t)) callback | n: quote.Node | {
        if quote.kind(n) == quote.CALL { seen = "${seen}<${quote.name(n)}>" }
    }
    return seen
}

twice(x: float) -> float { return x * 2.0 }

main() {
    println(calls() quote | x: float | -> twice(x) + twice(twice(x)))
}
```
```output
<twice><twice><twice>
```

`children(n)` hands the children over as a list, for a loop:
`kids = quote.children(n)`, `k, _ = list.get(kids, i)`, `k as quote.Node`,
then `list.free(kids)` (the nodes stay the tree's).

## Captures

A capture's cell is the variable itself, so the tree sees the program
change it. An outer local is moved into a shared cell for it; a global
(a program-level `var`) is its own cell, and the tree holds no reference
to it. Read the current value with the getter for its type:
`get_float`, `get_f32`, `get_int`, `get_long`, `get_bool`, `get_string`,
`get_ptr`, and `get_f32x4` for a lane type (a `vec2` declared
`distinct f32x4` reads through `get_f32x4`). A getter of the wrong type
panics naming both. `cell(c)` is the raw cell, for a struct
(`quote.cell(c) as *Texture`).

## Printing

`to_source(t)` prints the tree back as Aether (a `->` body comes back as
the block it stands for); `dump(t)` prints it as an s-expression with every
node's kind, name, operator, literal and type, which is what the regression
tests compare.
