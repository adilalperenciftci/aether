- **A call through the empty closure is a named panic.** `let c: fn =
  null` then `c()`, a closure field or parameter given `null`, and a `fn?`
  holding `null` (a present empty closure, which `match`'s `some` arm and
  `!` take) crashed with an access violation and no message. The call now
  panics with the category `empty_closure_call` and its source position,
  which a `catch` receives (#3091).
