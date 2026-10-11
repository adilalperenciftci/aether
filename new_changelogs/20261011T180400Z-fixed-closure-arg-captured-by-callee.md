- **A closure passed to a function that captures it in another closure is
  released.** The caller releases a closure argument after the call unless
  the callee keeps it, and a capture by a nested closure counted as a keep.
  That capture takes a reference of its own, as a field, a global or actor
  state does, so the caller's reference was the one left over: 2400 bytes
  per 100 calls, whether the capturing closure lived only for the call or
  was returned. A nested closure that rebinds the parameter still keeps it
  (#2754).
