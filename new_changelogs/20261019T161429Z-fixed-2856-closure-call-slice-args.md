- **`[]` and an array reach a closure's slice parameter.** The arguments of
  a call through a closure (`call(c, [])`, `c(arr)`) or a function pointer
  (a `fn(int[]) -> int` parameter, a function-pointer field) were not
  coerced into its parameters as a direct call's are, so `[]` and `null`
  reached C as an initializer list and a null pointer, and an `int[3]` as a
  pointer, where the closure takes a slice, and none of them compiled. They
  are the empty slice and a view of the array now, and an `if` whose arms
  are either is coerced arm by arm (#2856).
