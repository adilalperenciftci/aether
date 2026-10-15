# `quote`: a trailing block handed over as a tree

A fourth trailing-block form, beside the immediate block, the closure and
`callback` ([closures-and-builder-dsl.md](closures-and-builder-dsl.md)). The
compiler type-checks the block as ordinary Aether. Instead of compiling the
body to C that runs, it compiles it to C that **builds a tree describing the
body**, and passes that tree to the function as its last argument.

```aether,fragment
sky = shader("sky") quote | uv: vec2 | {
    t = time * 0.1
    return vec4(sin(uv.x * 10.0 + t), 0.0, 0.0, 1.0)
}
```

`shader` is an ordinary Aether function whose last parameter is a
`quote.Tree`. What it does with the tree (print GLSL, evaluate it on the
CPU, build a SQL `WHERE`) is library code. The compiler only knows how to
hand the tree over. The library to read it with is
[std.quote](../std/quote/README.md).

| Form | Written | The function gets |
|---|---|---|
| immediate | `f() { … }` | nothing: the block runs inline, in the function's context |
| closure | `f() \|x\| { … }` | a closure to call |
| callback | `f() callback { … }` | a closure to call |
| **quote** | `f() quote \| x: T \| { … }` | **a tree to read** |

The design was worked out for ae3d's shaders (the comparison throughout was
ChrysaLisp's shader language, where a shader is already an s-expression, so
Lisp gets for nothing the tree `quote` gives Aether; ideas only, no code).
The uses beyond shaders are in [Beyond shaders](#beyond-shaders).

## Syntax

```aether,fragment
f(args) quote | a: T, b: U | { body }     // parameters, a block
f(args) quote | a: T | -> expr            // parameters, one expression
f(args) quote { body }                  // no parameters
f(args) quote -> expr                   // no parameters, one expression
```

- **`quote` is not a keyword.** It means quoting only directly after a
  call's closing `)`, on the same line (the same-line rule the other forms
  keep), and before `|`, `||`, `{` or `->`. Nothing else can follow a call
  that way, so no reading of existing code changes. Everywhere else `quote`
  is an ordinary name, which matters because the module the tree lives in
  is itself called `quote` (`quote.Tree`, `quote.kind(n)`); a reserved word
  would have needed the same exception for every qualified use of it.
- **Parameters have types.** A closure parameter without one defaults to
  `int`; for a quote that would be a silent wrong guess, so an untyped quote
  parameter is an error (E0801).
- **The receiving function says it takes a tree.** Its last parameter is a
  `quote.Tree` (`import std.quote`). Passing a quote to a function whose last
  parameter is not one is an error, and so is passing a closure, a
  `callback` or an immediate block to one that is (E0802).
- A `->` body is the block it stands for: `quote | x: float | -> x * 2.0` is
  the tree of `{ return x * 2.0 }`.

## The tree

`quote.Tree`, `quote.Node` and `quote.Capture` are opaque handles read
through accessors ([std/quote/README.md](../std/quote/README.md) lists
them): `quote.child(n, i)` one child at a time, `quote.children(n)` all of
them as a list, and `quote.walk(n) callback | m: quote.Node | { ... }` every
node under `n`, a node before its children. The tree has:

- the **parameters**, each a name and a type;
- the **body**, a `BLOCK` node;
- the **captures**, one per outer variable the body reads (below);
- the **source**, `"file.ae:line"` of the quote, for a back end's errors;
- the **helpers**, the `@quotable` functions the body reaches
  ([Helpers](#helpers-quotable-functions));
- a **hash**, a 64-bit FNV-1a of the tree's shape (the format version, the
  parameters, the captures' names and types, and every node's kind, type,
  name, operator, literal and child count; then each helper's name, return
  type, parameters and body; not line numbers or the file), a
  constant the compiler computes, so a back end can cache what it made
  (GLSL, SPIR-V, native code) under it plus a hash of the back end itself.
  The same quote hashes the same in every build and wherever it moves in
  its file.

Each node has a `kind`, the `type` the type checker gave it, a `name`, an
`op`, a `lit`, its children and its `line`. Kinds, version 1:

| Kind | Children | Meaning |
|---|---|---|
| `BLOCK` | statements | `{ … }` |
| `LET` | value | `t = …` binding a new local (`name`, `type`) |
| `ASSIGN` | target, value | a write to an existing local; `op` is `=`, `+=`, …; `i++` is `i += 1` |
| `RETURN` | value (or none) | `return …`, including the one `->` makes |
| `IF` | cond, then, else? | `if` statement; an `else if` is an `IF` as the else child |
| `WHILE` | cond, body | `while` |
| `FOR` | init, cond, step, body | C-style `for (init; cond; step)` |
| `BREAK`, `CONTINUE` | | |
| `EXPR` | expr | an expression statement (a call made for its effect) |
| `LIT` | | `lit` holds `1`, `0.5`, `true`, the text of a string; `type` says which |
| `LOCAL` | | a local or a parameter, by `name` |
| `CAPTURE` | | an outer variable, by `name` |
| `UNARY` | operand | `op` is `-`, `!` or `~` |
| `BINARY` | left, right | `op` is any binary operator |
| `CHOOSE` | cond, then, else | `if a { b } else { c }` used as a value |
| `CALL` | arguments | `name` is the function as written, with its module (`math.sin`) |
| `FIELD` | object | `.x`; `name` holds the field |
| `INDEX` | object, index | `a[i]` |
| `MAKE` | a `FIELD_VALUE` per field | a struct literal, `Varyings { pos: p, uv: t }`; `type` is the struct |
| `FIELD_VALUE` | value | one field of a `MAKE`: `name` is the field (`pos`), the child its value |
| `HELPER_CALL` (version 2) | arguments | a call of a `@quotable` function; `name` is the function as the tree carries it (`quote.helper_named`) |

**Every node carries the type the type checker gave it.** A back end that
writes GLSL needs to know `t` is a `float` and `uv.x` an `f32`; it never
infers types again. A distinct type keeps its own name (`vec2`, not
`f32x4`), so a shader library gets GLSL's vector type names from the
checker.

The scalar types are Aether's, spelled as Aether spells them. `float` is a
C `double`; `f32` is the 32-bit float, C's `float`. A lane read from an
`f32x4`, or from a distinct type over one (`uv.x` for a `vec2`), is an
`f32`, because that is what the lane holds, the type `.x` has outside a quote
too. A literal beside an `f32` takes it (`uv.x * 10.0` is an `f32`), and a
`float` beside one widens the expression to `float`, as in C. A back end for
a language with one 32-bit float, GLSL's `float`, maps both `float` and `f32`
to it; a CPU evaluator keeps them apart, since they compute differently.

**A call is recorded, not made.** `sin(…)` becomes a `CALL` node named
`sin`. Nothing is called when the tree is built. The function still has to
exist and type-check, which is what makes a quote checkable at all: a
shader library declares `sin`, `vec4`, `texture`, `dot` as ordinary Aether
functions, and the same functions are its CPU evaluator.

**A constant reads as its value.** A program-level `const` with a literal
value is a `LIT` of that value (`HALF` is `LIT 0.5`). A program-level `var`
is a capture ([Captures](#captures)), since it can change.

`quote.to_source(t)` prints a tree back as Aether, and `quote.dump(t)` as an
s-expression with every node's kind, name, operator, literal and type:

```aether,run
import std.quote

show(t: quote.Tree) {
    defer quote.free(t)
    println(quote.to_source(t))
    println(quote.dump(t))
}

main() {
    show() quote | a: float, n: int | {
        total = 0.0
        for (i = 0; i < n; i++) {
            total += a
        }
        return if total > 1.0 { total } else { 0.0 }
    }
}
```
```output
| a: float, n: int | {
    total = 0.0
    for (i = 0; i < n; i += 1) {
        total += a
    }
    return if total > 1.0 { total } else { 0.0 }
}
(param a :float) (param n :int) (BLOCK (LET total :float (LIT 0.0 :float)) (FOR (LET i :int (LIT 0 :int)) (BINARY < :bool (LOCAL i :int) (LOCAL n :int)) (ASSIGN += (LOCAL i :int) (LIT 1 :int)) (BLOCK (ASSIGN += (LOCAL total :float) (LOCAL a :float)))) (RETURN :float (CHOOSE :float (BINARY > :bool (LOCAL total :float) (LIT 1.0 :float)) (LOCAL total :float) (LIT 0.0 :float))))
```

## Freeing a tree

Each evaluation of a quote builds a new tree, and the function it is handed
to owns it. A function that reads the tree and is done with it frees it,
`defer quote.free(t)` being the idiom (as `show` above does); one that keeps
it, in a struct or by returning it, hands that duty on with it, and whoever
holds it last frees it (`defer quote.free(shader.tree)`). `quote.free` also
gives back the tree's references to its captured cells.

A tree is not released at scope exit the way a heap string is. A string's
tracking follows a local the program binds; a tree is born as an argument,
inside a call, and whether the callee keeps it, returns it or drops it is
the callee's code, which the call site cannot see. Tracking it would mean
carrying the heap-string escape analysis (returns, struct fields, closure
captures, `try` frames) over to a second kind of owned value.

## Captures

An outer variable the block reads becomes a `CAPTURE` node, and the tree's
captures list holds one entry per variable: its name, its type, and its
**cell**.

**The cell is the variable itself, not a copy of its value.** The compiler
already moves a variable into a reference-counted heap cell when a closure
writes it; a quote moves every variable it captures there, so the variable
and the tree share the cell. When the program changes `time`, the next read
through the cell sees the new value:

```aether,run
import std.quote

keep(t: quote.Tree) -> quote.Tree { return t }

main() {
    time = 0.5
    t = keep() quote | x: float | -> x * time
    time = 2.0
    println(quote.get_float(quote.capture_named(t, "time")))
    quote.free(t)
}
```
```output
2.000000
```

That is what makes a shader's uniforms automatic: a shader library walks the
captures, declares a uniform for each, and each frame copies each cell's
current value into the uniform buffer. Nobody keeps a list of uniforms by
hand.

The tree holds a reference to each cell, so a tree can outlive the function
that built it: a captured local or **parameter** of that function stays
alive in its cell for as long as the tree does, and `quote.free(t)` gives
the references back. A quote inside a closure captures from the closure and
from the function around it alike.

A **global variable** (a program-level `var`) is a capture too, whose cell is
the global itself: nothing is moved, and the tree takes no reference to it,
since a global lives as long as the program. A light the program updates is
read through the tree like a captured local:

```aether,run
import std.quote

struct Light {
    power: float
}

var sun = Light { power: 1.0 }

keep(t: quote.Tree) -> quote.Tree { return t }

main() {
    t = keep() quote | x: float | -> x * sun.power
    defer quote.free(t)
    sun.power = 2.5
    println(quote.dump(t))
    lit = quote.cell(quote.capture_named(t, "sun")) as *Light
    println(lit.power)
}
```
```output
(param x :float) (capture sun :Light) (BLOCK (RETURN :float (BINARY * :float (LOCAL x :float) (FIELD power :float (CAPTURE sun :Light)))))
2.500000
```

The cell is read with typed getters (`quote.get_float(c)`, `get_int`,
`get_long`, `get_bool`, `get_string`, `get_ptr`, `get_f32`, and
`get_f32x4` for a lane type and the distinct types over one). A getter whose
type does not match the capture's panics with both types named. A struct is
read through `quote.cell(c) as *T`.

## Helpers: `@quotable` functions

A shader repeats small functions: a luma, a tonemap, a falloff. Written as
ordinary functions they would be `CALL`s a back end cannot write out, since
it has only their names. `@quotable` marks a function whose body is also a
tree:

```aether,fragment
@quotable
luma(c: vec3) -> float {
    return dot(c, vec3(0.299, 0.587, 0.114))
}

fxaa(screen: Texture, texel: vec2) -> *GpuShader {
    return fragment("fxaa") quote | uv: vec2 | {
        lc = luma(rgb(texture(screen, uv)))
        ...
    }
}
```

- A call of a `@quotable` function in a quote is a `HELPER_CALL`, and the
  quote's tree carries every `@quotable` function its body reaches, through
  its own calls or a helper's, **callees before their callers**: the order a
  back end that declares a function before its use (GLSL) writes them in.
  `quote.helper_count(t)` and `quote.helper(t, i)` list them,
  `quote.helper_named(t, name)` finds the one a `HELPER_CALL` names. Each is
  a `quote.Tree` with a name (`quote.function_name`), a return type
  (`quote.return_type`), its parameters and its body; it is freed with the
  quote's tree.
- The function stays ordinary Aether: the program calls it, and a CPU
  evaluator of the tree calls it as it calls `dot`.
- Its body is held to the same subset as a quote's, checked where it is
  defined, and it may read only its parameters and locals: it is written
  out as a function of its own, which has no way to reach the program's
  variables, and a shader's uniforms stay the quote's captures (E0805).
- A `@quotable` function that reaches itself through `@quotable` calls is an
  error (E0804): GLSL and MSL have no recursion.
- The quote's hash covers every helper it reaches, so editing a helper's
  body, even one reached only through another helper, changes the hash of
  each quote that reaches it, and a cache keyed on the hash goes stale with
  the edit.
- A helper in a module is named as the module's code names it once merged
  (`shaderlib_luma`), which also keeps two modules' `luma`s apart.

## What a quote may contain, and the errors

The block is type-checked as a closure body, then checked against version
1's subset. Each construct outside it is an error that names it, says why,
and points at its line:

```
error[E0800]: 'defer' can't be quoted
  --> sky.ae:14:9
14 |         defer cleanup()
   |         ^ help: a quote becomes a tree for a library to read; it has no 'defer' node
```

| Code | Rejected | Why |
|---|---|---|
| E0800 | a closure, `callback` or immediate block inside | a tree of trees has no back end to go to |
| E0800 | `defer`, `try`/`catch`, `panic` | control flow a shader, a query or an expression has no meaning for |
| E0800 | actor sends, `spawn`, `receive`, `reply` | ditto |
| E0800 | `match` (and `switch`) | not in v1; it would need the pattern kinds in the tree |
| E0800 | string interpolation | v1 keeps `LIT` strings only |
| E0800 | `heap.new`, an array literal, a cast, a tuple | v1 has no node for them |
| E0800 | a closure value; a `const` whose value is not a literal | v1 reads locals, parameters, captures (outer locals and globals) and literal constants |
| E0801 | a parameter without a type | a quote does not guess one |
| E0802 | a quote given to a function whose last parameter is not a `quote.Tree`; a closure, `callback` or immediate block given to one that is | the two sides have to agree on what is passed |
| E0803 | writing a captured variable, a global among them (`=`, `+=`, `++`), or taking its address | the cell is shared with the program; a quote reads it |
| E0804 | a `@quotable` function that reaches itself through `@quotable` calls | GLSL and MSL have no recursion |
| E0805 | a `@quotable` function reading a variable outside it | it is written out as a function of its own; pass the value as a parameter |

A `@quotable` function's body is checked against the same subset, where it
is defined; its errors say "can't be in a @quotable function".

The tests that hold each of these to its message and line are
`tests/integration/quote_errors/`.

## Versioning

The subset grows by adding kinds. That is the only way the tree changes:
**kinds are added, never removed or renumbered**, and `quote.VERSION` goes
up by one each time (it is 2: version 2 added `HELPER_CALL` and a tree's helpers). A tree records the version it was built with
(`quote.version(t)`). A back end that meets a kind it does not know reports
it with the node's line.

## ae3d's FXAA, written with `quote`

`tests/regression/test_quote_fxaa.ae` is ae3d's FXAA pixel shader written
this way, and checks the tree it makes. The uniform block, the sampler and
the `in`/`out` declarations of the GLSL disappear: uniforms are captures of
the function's parameters, the sampler is a captured texture, the `in` is the
parameter and the `out` is the return value.

```aether,fragment
type vec2 = distinct f32x4
type vec3 = distinct f32x4
type vec4 = distinct f32x4

fxaa(screen: Texture, texel: vec2, edge: float, edge_min: float, subpixel: float) -> Shader {
    return fragment("fxaa") quote | uv: vec2 | {
        luma = vec3(0.299, 0.587, 0.114)
        c = rgb(texture(screen, uv))
        n = rgb(texture(screen, uv + vec2(0.0, -1.0) * texel))
        // ... s, e, w and their lumas
        range = hi - lo
        if range < max(edge_min, hi * edge) {
            return vec4(c, 1.0)
        }
        // ...
        g1 = (if along { ls } else { le }) - lc
        off = if along { vec2(0.0, step * texel.y) } else { vec2(step * texel.x, 0.0) }
        return vec4(rgb(texture(screen, uv + off)), 1.0)
    }
}
```

`uv + vec2(…) * texel` type-checks as a `vec2` because the vector types are
distinct types over the `f32x4` lane type, which keep its operators; `vec3 +
vec4` is a type error, so the tree's types are GLSL's.

## How it is built

- **Parser** (`compiler/parser/parser.c`, `is_quote_trailing` /
  `parse_quote_trailing`): the trailing-block dispatch after a call's `)`
  checks for `quote` first, and reuses the closure parser for the
  parameters and body. Each call in the body keeps the name it was written
  with (`source_name`), since the checker rewrites `value` to the resolved
  name.
- **`AST_QUOTE`**, a node type of its own at the end of the enum, not an
  `AST_CLOSURE` with a marker: codegen special-cases closures in many
  places, and closure discovery would hoist it. Its children are the
  parameters, then the body, as a closure's are. The passes that treat a
  closure as a scope of its own (its `return`s are not the function's, its
  locals are not the function's) treat a quote the same way.
- **Type checking** (`typechecker.c`, `case AST_QUOTE`): a child scope with
  the parameters at their written types, the body checked as statements,
  then `quote_lower` (`compiler/analysis/quote.c`) checks the subset,
  resolves each name (the quote's own local, a capture of the enclosing
  scope, a literal constant), lowers the body to the tree with each node's
  type, and computes the hash. The body is then taken off the node: no
  later pass sees the quoted statements as code to run, and `value` is the
  quote's index in the lowered table. The callee check is
  `check_quote_callee`.
- **Captures**: closure discovery (`codegen_expr.c`) records the scope each
  quote is written in; `quote_promote_captures` promotes every capture to a
  cell there (`promote_up_from`, the same promotion a closure's written
  capture gets), and a quote inside a hoisted closure adds the variable to
  that closure's env first, so the nested-capture pass carries it out.
  A global (a program-level `var`) is neither promoted nor added to a
  closure's env: its cell is its own address, and the builder takes no
  reference to it. A bare `g = expr` write in the enclosing function binds
  `g` in that scope (it parses as a declaration); the binding is marked
  `global_write`, so the quote still resolves `g` to the global.
- **Codegen** emits, per quote, a static `_quote_build_N(void** cells)` that
  calls std.quote's runtime (`aether_quote_tree`, `aether_quote_node`,
  `aether_quote_add`, `aether_quote_param`, `aether_quote_capture`, …) to
  build the tree, taking a reference to each cell with the release that
  matches the cell's type; the quote's own site is a call to it with the raw
  cell pointers.
- **std.quote** is `std/quote/module.ae` (types, kinds, accessors, getters,
  printers) over `std/quote/aether_quote.c` (the node layout and the
  constructors), linked into `libaether` like the other std runtimes.

## Not done yet

- **Built once, shared.** Every evaluation of a quote builds a fresh tree;
  the parts without captures are the same every time and could be built
  once and shared.
- **Freed at scope exit.** A tree is freed by hand, `quote.free(t)`
  ([Freeing a tree](#freeing-a-tree)).
- **Uses outside the trailing position**, as a value
  (`q = quote | x: float | -> x * 2.0`): little extra once the trailing form
  exists, and the test-failure use below wants it. Not built.
- **Build time instead of start-up**: running the library at compile time,
  as a Lisp macro does, would mean running Aether inside `aetherc`. Not
  proposed now; the tree format does not rule it out.
- **More kinds**: `match`, interpolation (as a `CALL` of concat), casts,
  arrays, as back ends need them, each a version bump.
- **A local declared inside an `if` arm and read after it**, which Aether
  allows (the local is hoisted), reads in the tree as a `LOCAL` outside the
  block that declared it; a back end with C's block scoping has to hoist it
  itself.

## Beyond shaders

- **Test failures that show the expression.** `expect() quote -> a + b == c`
  lets the library print `a + b == c failed: a + b is 7, c is 8`, because it
  can evaluate each side of the `BINARY` node.
- **Query builders.** `where() quote | p: Person | -> p.age > 30` becomes
  `WHERE age > 30`.
- **Numeric functions**: a quote with arguments and no pixel, such as a
  matrix product or a physics step, can go to a CPU evaluator, to C, or
  later to GPU compute.
- **Symbolic maths and autodiff**, by walking and rewriting the tree.
- **aether-ui's** reactive bindings could see which state a computed value
  reads, instead of being told.
