- **A loop's local read before its binding has the binding's type.** In a
  `while` body, `out = "${out}${prev}"` ahead of `prev = "p${i}"` read the
  value the previous pass bound as an int and printed two pointer values.
  The checker declares a loop's or a branch's locals ahead of the block,
  typed from the inference pass before it, which left an interpolation
  untyped; it types it as a string now, so such a local is a string from
  its declaration, as a string literal or a string-returning call already
  made it (#2741).
