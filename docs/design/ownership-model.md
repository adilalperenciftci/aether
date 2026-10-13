# One ownership model

Status: proposal for sign-off. Nothing here is implemented yet.

## Why this exists

In two weeks (2026-09-29 to 2026-10-13) 429 issues were opened against
Aether, 415 of them by our own probes and reviews. The share that is about
ownership (who frees a string, a closure environment or a config, judged by
issue title) grew from 9% (Sep 29 to Oct 6) to 26% (Oct 7 to 12) to 37%
(Oct 13), and 28 of the 36 ownership issues filed on Oct 13 are still open. Each fix is correct for the
shape it covers, and the review of each fix finds the next shape: #2868 (an
`fn[N]` local never released its closures) led to #2876 (the same in a loop
body), which led to #2878 (an element handed back, the array captured) and
#2879 (the array in a cell). The list does not end because the model is a
list.

This document proposes replacing that list with one rule, applied the same
way to every kind of value in every place it can live.

## The model today

[memory-management.md](../memory-management.md) describes about fifteen
rules, each a section of its own. In short:

- **A `string` has several physical shapes.** A literal is static `char`
  data. A fresh string from the runtime (`string_concat`, interpolation,
  `string.from_int`, ...) is a refcounted `AetherString`, recognised by a
  magic header. A literal that holds a NUL is a static `AetherString` pinned
  so it is never counted (#2520). A `char*` from C is whatever C says.
  `string_retain` and `string_release` do nothing to a value without the
  header, so the runtime cannot tell an owned plain buffer from a borrowed
  one.
- **Ownership is tracked per variable, not per value.** Each string local
  has a `_heap_<name>` flag the compiler sets on every assignment from what
  it can prove about the right-hand side. Every other place a string can
  live (a struct field, an array element, a tuple slot, an optional, a
  module variable, a closure cell, a container, a builder config, a message)
  needed its own flag or its own convention, and each was added by an issue.
- **Transfers are decided by reading the callee's body.** Whether a caller
  frees what it passed depends on whether the callee keeps, frees or
  returns the parameter (copy-on-keep, `@retain`, `@noescape`, the
  hand-back rules); whether a caller frees what it got back depends on a
  classification of every `return` in the callee (the uniform-heap wrap, the
  pass-through veto, the per-position tuple classifier, the cycle rules of
  #2870 and #2875). These analyses are whole-program, can loop through
  recursion, and stop at a binary import (#2860, #2861).
- **Closure environments are already counted** (#2494), with atomic counts,
  and a holder takes a reference of its own (#2525, #2528). Structs that own
  strings or closures have generated `_destroy`, `_dup` and `_replace`
  functions. These are the parts of today's model that converged.

The pattern behind the open issues: wherever the compiler cannot see which
shape a value has, or which body a call reaches, it guesses, and each wrong
guess in a new place is a new issue. The parts that converged are the ones
where the value carries its own count.

## The proposal

Five rules. Each is a statement about every value kind and every place, with
no exceptions listed per shape.

### R1. Every owning value carries its own count

- Every `string` the program holds is an `AetherString`: the runtime's
  producers already return one, a literal is emitted as a static pinned
  `AetherString` (as #2520 already does for literals holding a NUL), and a
  `char*` that comes in from C is adopted or copied once, at the extern
  boundary (R4).
- Closure environments keep their count (they have one today).
- A struct, tuple, optional or fixed-size array that holds owning values is
  not counted itself. It is a composite whose copy, destroy and move are its
  parts' copy, destroy and move, generated per type (the `=copy`, `=destroy`
  and `=sink` hooks of #484, which the generated `_dup` and `_destroy` of
  structs already are in all but name).

Consequence: `release` is always correct on any string value, and the
`_heap_<name>` flags, the "is this expression heap" classifier and the
uniform-heap return wrap have nothing left to decide.

### R2. Every place holds exactly one reference to what it holds

A place is anything a value can be stored in: a local, a parameter the
callee stores, a struct or message field, an array or slice element, a tuple
slot, an optional's payload, a module variable, a closure cell or captured
variable, a container slot, a builder config, an actor's state.

### R3. Three operations, the same everywhere

- **Store** into a place: take a reference to the new value, then release
  the value the place held. A temporary that dies at the store is moved
  instead (no count change). This one rule replaces the per-place "adopt,
  move, copy or borrow" decisions.
- **Leave** a place (scope exit on every path, `break`, `continue`,
  `return`, a caught panic; a struct, array or container destroyed): release
  what it holds.
- **Pass** a value to a parameter: the callee borrows it for the call. If
  the callee stores it, that store is R3's store and takes its own
  reference. The caller never needs to know what the callee does with it.
- **Return**: the callee hands the caller one reference. A value it only
  borrowed (a parameter, a global, a field of a parameter) is retained at
  the `return`.

No rule depends on reading another function's body, so no rule changes at a
binary import, a recursive cycle or a clause set.

### R4. C boundaries are the only place that needs annotations

An extern returning `char*` is borrowed unless declared `@heap`; a borrowed
one is copied into an `AetherString` when it is stored, an `@heap` one is
adopted once. A `string` passed to C is passed as its character data. This
is today's `@heap`, `@borrow`, `@retain` and `@noescape` vocabulary, kept
for C and no longer needed for Aether functions.

### R5. Optimisations may remove counting, never decide ownership

Moving on last use, eliding a retain and release pair, and borrowing instead
of retaining a parameter that is only read are optimisations over R1 to R4.
When one is wrong or missing, the program does one count operation too many;
it does not leak or free twice. Today the same analyses decide correctness,
which is why a gap in one is a leak or a use after free.

## What it settles

Decisions that are open today, each an instance of R2 and R3:

- **#2871, #2860, #2861 (a builder's config):** the config is a place the
  builder call owns. A setter that keeps `_ctx` stores it (R3), so it holds
  its own reference; the call releases its reference when it returns. A
  factory that returns a shared object returns a retained reference (R3's
  return). No rule about what a builder body names.
- **#2747 (a store through a `string[]` slice element):** a slice is a view;
  storing through it stores into the element of the array it views (R3).
- **#2822 (an optional field that owns memory):** an optional's payload is a
  place (R2); copy and destroy are its payload's.
- **#2808 (module-level strings never given back):** a module variable is a
  place; a re-bind is a store.
- **#2869, #2836, #2844 (tuples):** a tuple slot is a place; a tuple local
  owns its slots; a thrown-away tuple is left at once.
- **#2878, #2879 (closure arrays):** an element is a place holding a
  reference to an environment, as a closure local does today.

The other open ownership issues (#2786, #2788, #2814, #2825, #2828, #2849,
#2852, #2858, #2872, #2875) are shapes where today's analyses guess wrong.
Under R1 to R3 there is nothing to guess. Each becomes a cell of the test
grid below and is closed by the stage that makes its cell pass, not by a
fix of its own.

## What it costs, and the risks

- **Count traffic.** Every store of a string that is not a dying temporary
  becomes a retain. Parameters stay free (R3 borrows), and R5's moves remove
  most stores of fresh values. Interpolation moving to the refcounted shape
  cost +1.6% on a loop that does nothing else (memory-management.md). The
  benchmark suite gates each stage; a stage that costs more than its
  measured budget does not merge.
- **Threads.** `AetherString` counts are plain `int`s, while closure
  environments use atomic counts. A string must not be shared by count
  between actors. Proposal: a send copies a string unless its count is 1,
  in which case it moves. This needs checking against what the send side
  does today before stage 2.
- **Cycles.** A closure environment that ends up holding itself (a closure
  stored in a cell it captures) is never freed by counting. That is today's
  limit too; the model does not make it worse, and a cycle check is out of
  scope here.
- **C code that holds an Aether string past a call** (a C library keeping a
  `const char*`) must copy it or be declared `@retain`, as today.

## How to get there

Each stage ships on its own, keeps the full test suite and the leaks gates
green, and is measured against the benchmarks before it merges.

1. **The grid first.** A generator writes one test program per cell of
   value kind (string, string?, closure, `fn[N]`, struct owning strings,
   tuple with strings, builder config) by place (R2's list) by transfer
   (store, re-store, leave on each exit path, pass, keep, return, hand
   back, send, catch a panic). Each program checks its values, checks
   `mem.steady_growth` is 0, and runs under the poisoning allocator. Run on
   main, it is the map of what is broken today; from then on it replaces
   probing by hand and filing one issue per shape.
2. **R1:** every string an `AetherString`; literals pinned; C strings adopted
   or copied at the boundary.
3. **R2 and R3:** one generated take and drop per type, used by every
   place; the per-place paths go.
4. **R3's transfers:** parameters borrow, the callee's own store retains,
   returns hand over. The callee-body analyses go: copy-on-keep, the return
   classifier, the pass-through veto, the tuple and cycle classifiers.
5. **R5:** last-use moves and pair elision, each measured.
6. **Docs:** memory-management.md rewritten around R1 to R5; the per-shape
   sections become history.

## Decisions needed

1. R1: is every Aether `string` an `AetherString` (pinned for literals)?
   This changes what C sees through `--emit=lib` and bindgen, which must be
   checked in stage 2.
2. R3: parameters borrow and a callee that stores takes its own reference,
   for every Aether function, with the C-only annotations of R4.
3. Sends: copy a string unless it is uniquely held, or make string counts
   atomic.
4. The order: no new per-shape ownership fixes from now on. Ownership
   findings go into the grid, and the stages close them.
