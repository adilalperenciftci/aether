- **A slice's buffer is released when the local that owns it goes out of
  scope, and `xs.push(v)` grows a slice in place.** A buffer `make([]T, n)`
  hands out, or `append` or `push` grows, has one owner: the local holding
  it releases it, and what its elements hold, on every exit of its scope (the
  end of the block, `return`, `break`, `continue`, a caught panic), so a
  program writes no `free` for it. Before, every such buffer leaked unless
  the program freed it by hand. A buffer moves: `ys = xs`, returning it,
  storing it in a field, a `var`, an element, a struct, a tuple or a message,
  and giving it to a parameter declared `xs: @keep T[]` leave `xs` empty, and
  using `xs` after a move, `free(xs)` or `append(xs, v)` is a compile error
  (E0906, new); `v = xs[..]` is a view that leaves it in place. A parameter
  borrows: `free`, `append` and `push` on one that is not `@keep` are E0901
  (functions that freed or grew a slice parameter now declare it `@keep`),
  and a copy read out of a parameter, a field, an element or a `var` is
  marked a view, so nothing frees through it. A slice of slices owns its
  rows: a store into a row releases the one it replaces, and `free` of the
  outer slice releases every row. A buffer a view of which may outlive its
  local (returned, stored, kept by a callee, bound in an outer scope) is not
  released, as before ownership. `free(xs)` and `defer free(xs)` still work
  and leave the place empty. Buffers held by fields, `var`s, tuples and
  messages, and slice locals a closure captures, are still freed by hand.
