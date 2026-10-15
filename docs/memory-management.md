# Aether Memory Management

Aether's memory model is **deterministic scope-exit cleanup**, not garbage collection.

The guiding principle:
> **Allocations visible at call site. Cleanup explicit and composable. `defer` is your primary tool.**

Allocations are visible at the call site, and there are no GC pauses.

### Why `defer`?

1. **Visible** -- you can see every allocation and its cleanup in the source
2. **Composable** -- works with any function, not just stdlib types
3. **Predictable** -- no special naming conventions, no hidden registry, no surprises
4. **Familiar** -- same pattern as Go's `defer` and Zig's `defer`

The one-line cost (`defer type.free(x)`) is the price for knowing exactly what your program does.

---

## The Actual Model

Aether uses two allocation mechanisms:

| Layer | What | When |
|-------|------|------|
| **Actor allocation** | Actor state + inline mailbox | One NUMA-aware allocation per actor, freed when the actor is destroyed |
| **Stdlib heap** | `map.new()`, `list.new()`, etc. | Freed via `defer` or explicit `.free()` call |

There is **no garbage collector**.

### Arena vs defer: when to use which

They solve different problems and are used in different layers:

| | Arena | defer |
|---|--------|--------|
| **What** | A region of memory; many small allocations share one region. One "free" destroys the whole region. | A language construct: run cleanup when leaving the current scope. |
| **Who uses it** | A general-purpose arena allocator backs bulk-allocation use cases such as `std.arena` and JSON parsing. You opt into it explicitly. The actor path does **not** use arenas. | **You** use it in Aether code for stdlib types (`list.new`/`list.free`, `map.new`/`map.free`) and FFI buffers. |
| **Lifetime** | Everything in the arena lives until the arena is destroyed in one shot. | The resource lives until scope exit; the deferred call runs then. |
| **Typical use** | Bulk allocation where many objects share one lifetime and are reclaimed together (e.g. all nodes of a parsed JSON document). | Any heap allocation you make: `items = list.new(); defer list.free(items);` so the list is freed when the function (or block) exits. |

---

## Stdlib Convention

All stdlib types follow one consistent naming pattern. In Aether you call them with dot syntax; the underlying C functions use underscores (`type_new`/`type_free`):

```
type.new()    -> allocates on the heap, returns a pointer (must be freed)
type.free(t)  -> frees the allocation
```

| Module | Constructor | Destructor |
|--------|-------------|------------|
| `std.map` | `map.new()` | `map.free(m)` |
| `std.list` | `list.new()` | `list.free(l)` |
| `std.string` | `string.new()` | `string.free(s)` |
| `std.dir` | `dir.list(path)` | `dir.list_free(l)` |

**Rule**: Any function whose name ends in `_new()` or `_create()` (at the C level) returns an allocated object. Its matching `_free()` is its destructor. In Aether, use `type.new()` and `type.free(x)`.

---

## The `defer` Pattern

Aether's primary memory management pattern is `defer`: allocate, immediately defer the free, then use the resource. Cleanup runs at scope exit in LIFO order, on every exit: a `return`, a `break`, or a panic a `try` catches further up.

```aether
import std.map

main() {
    m = map.new()
    defer map.free(m)

    map.put(m, "k", "v")
    print(map.get(m, "k"))
    print("\n")
    // map.free(m) runs here (scope exit)
}
```

This is explicit, visible, and composable. It works with any function -- not just stdlib types.

### Multiple allocations

```aether
import std.list
import std.map

main() {
    m = map.new()
    defer map.free(m)

    items = list.new()
    defer list.free(items)

    // Use both...
    // At scope exit: list.free(items) runs first (LIFO), then map.free(m)
}
```

### Returning allocated values

When a function allocates and returns a value, the caller receives ownership:

```aether
import std.list

build_items(n) : ptr {
    result = list.new()
    i = 0
    while i < n {
        list.add(result, i)
        i = i + 1
    }
    return result
}

main() {
    items = build_items(10)
    defer list.free(items)

    print(list.size(items))
    print("\n")
}
```

---

## Actor State

Actor `state` variables initialized with `*.new()` outlive any single message handler. Free them in the actor's `Stop` handler (or wherever the actor is shut down):

```aether,fragment
import std.map

message Store { key: string, value: string }
message Lookup { key: string }
message Stop {}

actor Cache {
    state data = map.new()

    receive {
        Store(key, value) -> {
            map.put(data, key, value)
        }
        Lookup(key) -> {
            print(map.get(data, key))
            print("\n")
        }
        Stop() -> {
            map.free(data)
        }
    }
}
```

The actor runtime frees the actor's single NUMA-aware allocation (the actor struct and its inline mailbox) when the actor is shut down. Stdlib allocations held in `state` fields are not part of that block, free them yourself, e.g. in the `Stop` handler above.

---

## Common Mistakes

**Forgetting `defer` after allocation:**

```aether,fragment
m = map.new()
map.put(m, "k", "v")
// LEAK: m is never freed
```

Fix: always pair allocation with `defer`:

```aether,fragment
m = map.new()
defer map.free(m)
```

**Deferring before the allocation succeeds:**

`defer` registers immediately. Place it right after the allocation, not before.

**Allocating inside a loop:**

`defer` is block-scoped: a `defer` placed inside a loop body fires at the end of
each iteration, not just once at function exit. So an allocation made inside the
loop is reclaimed every pass, no manual per-iteration free is needed:

```aether,fragment
while i < n {
    item = list.new()
    defer list.free(item)   // runs at the end of THIS iteration
    // ... use item ...
    i = i + 1
}
```

---

## Summary: When to Use What

| Situation | Approach |
|-----------|----------|
| Typical local allocation | `defer type.free(x)` right after allocation |
| Value returned from function | Caller defers the free |
| Value passed to an actor via `!` | Actor owns it; no defer in sender |
| Actor `state` initialized with `*.new()` | Free in `Stop` handler: `map.free(data)` |

---

## Values the program owns

Strings, closures and the composites built from them (structs, tuples,
optionals, fixed-size arrays) are managed by the compiler, with no `defer`
and no garbage collector: every value is released at a point the source
shows. Five rules decide where (the design and its record are in
[design/ownership-model.md](design/ownership-model.md)):

- **R1, every value carries its own count.** A `string` is a counted
  `AetherString`; a literal is pinned (its count never changes and it is
  never freed). A closure's environment is counted. A composite owns each of
  its parts.
- **R2, every place holds one reference.** A local, a parameter's copy, a
  struct, tuple or optional field, an array element, a module `var`, an
  actor's state field, a message field, a list or map element, a closure's
  captured variable: each owns what it holds.
- **R3, a store takes and a scope exit releases.** A store takes the new
  value and releases the one it replaces; leaving a scope releases what its
  locals hold, on every exit (a `return`, a `break`, a caught panic). A
  parameter is borrowed: the callee never releases it, and one it keeps it
  takes a reference to. A call borrows its arguments, so a fresh argument
  is released after the call; a function returning a value hands its caller
  one reference.
- **R4, only C boundaries are annotated** (below).
- **R5, moves.** Taking a fresh value (a call's result, an interpolation)
  moves it; so does taking a local at its last use, which leaves the local
  empty. Otherwise a take retains a counted string, passes a pinned literal
  as it is, and copies a plain C string.

No rule reads another function's body: what a call does with its
arguments, and what it hands back, is decided by the callee's signature.

```aether
import std.string

label(n: int) -> string {
    s = "item-${n}"                 // owns the interpolation
    return s                        // moves it to the caller
}

main() {
    a = label(1)                    // a owns the result
    b = a                           // b takes a reference; a still owns its own
    a = string.concat(b, "!")       // releases the old value, owns the new one
    println("${a} ${b}")
}                                   // a and b are released here
```

### Strings

A string local owns the value it holds, whatever it was given: a literal, a
call's result, another local, a field read. `string.free(s)` or
`release(s)` on a local releases its reference early and leaves the local
empty; on a parameter it is refused (E0901), since the function does not own
it. Strings are immutable once made, so two places sharing one counted
string is safe; a string stored where other threads can read it (a module
`var`, a closure environment, a value reached through a pointer) is
published, and its count becomes atomic from then on.

### Closures

A closure literal's environment is counted. A local holding a closure owns a
reference; capturing a variable takes one; a closure field, element or state
field takes one; a closure passed to an `fn` parameter is borrowed. A
variable a closure writes lives in a shared cell, counted the same way, so
the closure and its creator see one value.

### String sequences

A `*StringSeq` is counted per cell and owned like a closure: every place
holding one owns a reference, a fresh sequence (a literal, an Aether
function's result, a `string.seq_*` producer's) moves in, any other is
retained, and `string.seq_tail` lends. The counts are atomic, so a sequence
crosses actors by reference. See docs/sequences.md.

### Structs, tuples, optionals and fixed-size arrays

Each owning type has one generated retain and one drop, which every place
uses: a copy retains every part, a drop releases every part. A struct
parameter is borrowed; one its body writes into is copied on entry. A
struct boxed with `heap.new(T)` owns its fields as a local struct does, and
`heap.free(p)` releases them before it frees the box. A
fixed-size array is held by value wherever it goes: a local, a field, a
message field, an optional's payload, a function's result (returned in a
struct of its own), a temporary passed as an argument.

### Containers, module variables, actor state, messages

`list.add`, `list.set` and `map.put` take a reference to a string or a
closure, released when the element leaves (`list.remove`, `list.clear`, a
store over it, `map.remove`, `free`); a `list.set` that fails gives back what
it was handed. A module `var` and an actor's state field take what is stored
and release what they replace; the actor's state is released when the actor
is destroyed. A message owns its fields: the send takes them, a receive arm
reads them in place, and the message is released after the arm. What the
arm keeps (in state, in a container) it takes.

### C boundaries (R4)

C sees a string as its characters. An extern borrows what it is given for
the call. An extern that keeps a value declares the parameter `@retain`: the
call then hands it a reference of its own (a fresh value as it is, a place's
retained), for a `string` and for a closure. `@aether` passes the counted
string itself, for C written against Aether's runtime. `@noescape` states
what a parameter that is not `@retain` already is.

An extern returning a fresh string declares it `@heap` (`-> string @heap`;
`-> ptr @heap` for a counted string returned untyped, as `string.from_int`
does; per position of a tuple result, `-> (string @heap, int, string)`); the
string is adopted at the call, and the caller owns it. Any other string an
extern returns is C's and is copied when a place takes it.

A string stored into a header-defined struct's field (`extern struct ...
@c_import`) or into a slice over C memory is given a reference of its own,
which nothing in the program releases: it is C's from then on.

### `ptr` slots

A `ptr` slot owns nothing. A string goes into one only through
`string.keep(s)`, which hands over a reference the program gives back with
`string.release_kept(p)`; a closure goes into one boxed (`box_closure(f)`,
or the coercion a store into a `ptr` makes), the box holding a reference of
its own, which `release_closure(p)` gives back. A function that keeps a
`ptr` parameter declares it `@keep` (E0902); a `ptr` parameter that only
borrows is given a closure in a box on the caller's stack, so nothing is
allocated.

### Panics

A panic caught by a `try` releases what the scopes it leaves hold, as their
exits would have: every owning local, temporary and argument is recorded in
an unwind journal while it is live, and every plain `defer` of those scopes
runs, newest first. `defer try` and `defer catch` do not run on a panic.

### `@scoped` bindings, checked non-escape

A `let`/`var` declaration can be annotated `@scoped` to declare that its value
**must not outlive the lexical block** that introduced it. This is opt-in
escape analysis, not a borrow checker (Aether has none). It turns a footgun
into a compile-time invariant and documents intent at the binding site:

```aether,fragment
process() -> long {
    @scoped buf = make_buffer(64 * 1024)
    return buf.checksum()        // ok, a scalar DERIVED from buf escapes
}

leak() -> *Buffer {
    @scoped buf = make_buffer(64 * 1024)
    return buf                   // compile error: the @scoped binding escapes
}
```

The typechecker rejects every way the binding's value could outlive the block:

- returning the binding,
- assigning/aliasing it into another binding or a struct field,
- placing it as an element of an array / struct / message literal,
- capturing it in a closure (closures lower to plain C functions, so their
  lifetime is statically known),
- inserting it into a container (`list.add`, `map.put`, `set.add`, …).

Only a value *derived* from the binding via a call (`buf.checksum()`,
`string.length(buf)`) may escape, that carries the call result, not the
binding. A value handed to a function that retains it beyond the call is
governed by that function's own contract; `@scoped` checks the direct escape
sites at the binding's own scope.

### Cycles

Counting does not free a cycle: a closure stored in a cell it captures, or
values that hold each other through `ptr` slots, live until the program
ends. Break the cycle (store `none`, release the slot) before dropping the
last outside reference.

### History

Before this model, each value kind and place had its own mechanism: a
per-variable ownership flag for strings (`_heap_<name>`), an escape walk
that kept a value alive when it might be stored, a uniform-heap wrapper on
returns, a copy-on-keep analysis of callee bodies, and per-struct field
trackers. Each fixed one shape and its review found the next. They are
replaced by the rules above; the tracking issue (#2918) lists the issues
that recorded them, and the implementation record is in
[design/ownership-model.md](design/ownership-model.md).

## Examples

See the following runnable examples:

- [examples/basics/memory_defer.ae](../examples/basics/memory_defer.ae) -- defer pattern (recommended)
- [examples/basics/memory_manual.ae](../examples/basics/memory_manual.ae) -- manual free pattern
- [examples/basics/memory_escape.ae](../examples/basics/memory_escape.ae) -- returning allocated values
