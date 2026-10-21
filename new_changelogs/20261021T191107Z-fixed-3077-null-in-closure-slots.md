- **`null` is the empty closure in every closure slot, `fn?` ones
  included.** `let o: fn? = null`, a `fn?` field, parameter or re-bind
  given `null`, a tuple literal's `null` part (`(null, 1)`), a module
  `fn?` var re-bound to `null`, `o ?? null`, an all-`null` literal in a
  `fn[2]` slot and `o == null` on a `fn?` failed in the C compiler; `return
  null` from `-> fn?` and `[held, null]` beside a `fn?` were refused. Each
  takes the empty closure now: a `fn?` given `null` holds it, as a `ptr?`
  given `null` holds a null pointer, so it is not `none`, and `o == null`
  is true. `==` between two `fn?`, or a `fn?` and a closure, which also
  failed in C, is a compile error, as between two closures (#3077).
