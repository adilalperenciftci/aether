- **A reply's value is type-checked.** `reply label ?? "none"` sent an
  `int`: the value of a `reply` was never checked as an expression, so a `??`
  (or anything whose type that check sets) stayed untyped, and both the
  reply and the asker took it for an int. It is now checked as a `return`'s
  value is (#3301).
