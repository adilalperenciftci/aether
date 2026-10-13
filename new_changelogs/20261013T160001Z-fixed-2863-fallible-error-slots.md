- **A fallible function's built error string is freed.** A `T!` function
  that returns a bare value on success and builds its error on another path
  (`return "", string.concat("bad-", w)`) had the error position of its
  result taken for an unfreeable passthrough, so the `or`, the destructure
  and `_, _ =` that discarded the error never freed it. The position is now
  heap whenever a return builds its error, and the success sentinel is a
  string the caller owns as well. `x!` reads the error slot as the `or` does
  (an owned empty slot read raw looked like an error, so `x!` panicked on
  success), frees the sentinel on success, and a propagating `x!` copies a
  literal error it hands on into a position the caller frees (#2863).
- **`x!` in main() compiles after a `T!` function.** The function emitted
  before main left its result type in place, and main's `x!` was lowered as
  a propagation returning the result tuple from `main` (#2864).
- **A tuple's heap strings are freed when nothing binds them.** A tuple call
  thrown away as a statement (`pair(w)`), and `f()!` over a tuple whose first
  slot is a heap string used in place (`pair(w)! == x`), left the strings to
  nobody (#2865).
