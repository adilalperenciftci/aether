- **`defer f(_builder)` in a builder compiles again.** A plain `defer` is
  journaled with a panic thunk (#2923) that copies the locals its statement
  reads out of a cell, and a builder's hidden `_builder` parameter was not
  among the names the codegen knew were declared, so the thunk named an
  undeclared `_builder` and the C did not compile. The hidden parameter is
  now declared like a named one, so a defer reading it runs on a return and
  on a caught panic. A 0.818.0 regression, found by datastar-aether.
