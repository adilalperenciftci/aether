- **A closure can capture a `catch` binding or a `some(v)` binding.** A
  closure in a `catch e` handler that used `e`, or in the `some(v)` arm of
  a match over an optional that used `v`, read an undeclared name in its
  C body: capture discovery counted only declarations and parameters as
  the enclosing function's locals. It worked only when the function also
  had a local of the same name. Both bindings are captured now, typed as
  the panic's reason string and as the optional's value, and the
  closure's environment takes a reference of its own to a string it
  captures, as for any string local (#2769).
