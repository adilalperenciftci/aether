- **An inferred result read through a pointer can be an optional.** A
  function with no written result type that returns an optional read
  through a pointer after a none-check (`o = p.opt`, `if o != none { return
  o }`, `return none`, or `if o == none { return none } else { return o }`)
  returns that optional, `T?`, as it does when the early pass can type `o`;
  0.836.0 took its result for an int, so a `??` on it was refused (#3056).
