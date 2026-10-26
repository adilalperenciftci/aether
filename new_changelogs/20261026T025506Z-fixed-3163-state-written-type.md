- **Actor state takes a written type.** `state next: actor_ref = null` was
  three "Unexpected token in actor body" errors and the type-first form
  refused `actor_ref` too, so an actor held a reference only as a bare
  `state next = null`. A state now takes `name: T`, with a value or
  without one (its type's zero), for every type a struct field takes, and
  `state actor_ref r` is accepted; the value is checked against the written
  type as a typed binding's is (it reached C, "makes integer from pointer"),
  and an optional state's value is wrapped as `let x: T? = v` wraps it (an
  int was assigned to an ae_opt_int) (#3163).
