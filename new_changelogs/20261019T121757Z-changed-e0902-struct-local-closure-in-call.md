- **E0902 counts a struct or a closure only when it escapes.** A `ptr`
  parameter put in a struct local to the function, or captured by a closure
  that runs and is dropped inside the call, no longer has to be declared
  `@keep`: neither outlives the call. The struct or the closure is a keep
  only when it escapes itself, returned, stored in a field, a module-level
  `var` or a container, or passed to a `@keep` or `@retain` parameter, and
  each of those is still E0902. A closure that stores the pointer somewhere
  that outlives the call keeps it too. Downstream, aephysics' query
  functions, about a dozen of ae3d's and aeb's builder can drop their
  `@keep` once this is released.
