- **A function that keeps a `ptr` parameter says so: `p: @keep ptr` (E0902).**
  A `ptr` owns nothing, so a string passed where a `ptr` is expected and kept
  there was freed under it by its owner; the compiler kept the caller's
  value alive by reading the callee's body, and leaked it. Now a `ptr`
  parameter is borrowed for the call unless declared `@keep`, and each
  function is checked against its own body: storing a borrowed one where it
  outlives the call, returning it, capturing it, or passing it to a `@keep`
  parameter is refused, naming the parameter. A `string` reaches a `@keep`
  parameter only through `string.keep(s)`; `string.release_kept(p)` gives
  that reference back. A closure's `ptr` parameter is always borrowed, and a
  function with a `@keep` parameter is called by name. Breaking: code that
  keeps `ptr` parameters adds `@keep`; std, contrib and the tests carry 329
  such annotations (#2926).
