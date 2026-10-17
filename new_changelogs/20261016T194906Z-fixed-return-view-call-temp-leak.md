- **`return f("x ${i}")`, where `f` returns a `ptr` or a slice, releases
  the string it passed.** Since 0.818.0 such an argument lives to the end of
  its statement (the result may be a view into it), released by the
  statement's block on every exit. A `return` with no exit work of its own
  was written as a bare `return v;`, so that release landed after it and
  never ran: each call leaked the argument, and a module `var` or a field
  held for the call leaked its reference. Such a return now goes through
  the exit drain, which releases them once the value is computed. Found by
  ae3d.
