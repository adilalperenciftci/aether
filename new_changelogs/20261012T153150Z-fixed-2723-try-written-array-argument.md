- **An array a `try` body writes can be passed to a `T[N]` parameter.** Its
  elements are volatile (#2690), and the callee's plain `E _param_a[N]`
  discarded the qualifier: a warning, an error under `-Werror`. A `T[N]`
  parameter is a value its callee copies, so such an argument (a local
  array, an array field of a local struct, a parameter array, for a
  function or a closure) is now copied into an array of the call's own,
  read through a volatile pointer; any other argument passes as before
  (#2723).
