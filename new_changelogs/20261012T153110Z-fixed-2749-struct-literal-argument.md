- **A struct literal passed straight to a call is destroyed after it.** A
  function or closure borrows a struct parameter (it disowns the copy's
  strings on entry, or takes references of its own when it keeps the
  value), so `reader(Item { name: string.concat(w, "old") })` left the
  literal's strings to the caller, and nothing destroyed them: every call
  leaked them, while the same literal bound to a local first was
  destroyed at the local's scope exit. Such a literal is now a temporary
  of its statement, as a struct a call returns is (#2582), destroyed once
  the statement is done, nested literals and closure calls included; a
  string the callee hands back from it is copied where the call is made,
  so it outlives the literal (#2749).
