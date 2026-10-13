- **A closure's tuple destructure writes outer locals a destructure bound.**
  `a, b = three()` followed by `bump = || { a, b = two() }` left `a` and
  `b` as they were after `bump()`: the lookup of the outer binding a
  closure writes through took a statement for a binding of `a` only when
  it was a single `a = ...`, so the closure's destructure declared locals
  of its own. A tuple destructure is a binding of every name it binds now,
  so the closure writes the outer `int`, `string` or `fn` slots through
  their cells, in a function, in `main`, in a loop body and from a closure
  nested in another (#2762). Each slot that re-binds a local, outer or in
  its own scope, is checked as `a = 7` is: a slot of another kind is the
  "cannot re-bind" error at the slot, a float into an inferred `int` the
  narrowing error, and a value C converts is stored as the local's type.
  Before, such a slot reached the C compiler (`assignment to 'const char *'
  from 'int'`) or truncated silently.
