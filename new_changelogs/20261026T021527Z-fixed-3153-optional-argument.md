- **An optional is not unwrapped into a function's parameter.**
  `shout(maybe(1))`, a `string?` given to a `string` parameter, passed the
  checker and failed in C ("incompatible type for argument 1 ...
  ae_opt_string"), as it did through a local; a binding, a `return` and a
  field already refused it. It is E0200 at the argument now, naming
  `?? fallback`, `!` and `match`. A local bound to a `T` in one branch or
  loop body and to a `T?` in another is one `T?` variable, in C as in the
  checker: the `string` loop first declared a `const char*` that the other
  loop's `ae_opt_string` could not be stored in, and the diagnostic for
  such a local names the other binding (#3153).
