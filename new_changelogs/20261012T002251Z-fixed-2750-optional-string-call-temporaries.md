- **A `string?` call result nobody binds is freed.** A function returning
  `string?` hands its caller a string of its own (#2740), but a result
  used without binding it was freed by nobody: under `!` and `??`, in a
  comparison, an interpolation, as a call's argument, as a `match`
  scrutinee or thrown away, one string leaked per evaluation, even
  `lookup(true)! == "Ada"` over a function returning a literal (since
  #2740 copies it). It is now a temporary of its expression: `f()!` and
  `f() ?? d` yield a heap string of their own (the default copied unless
  it is fresh) that whatever reads it frees or takes, `f() == none` frees
  it after reading the flag, an argument is freed after the call when the
  parameter keeps nothing, a `match`'s `some` binding owns it for its arm,
  and a discarded one is freed (#2750).
