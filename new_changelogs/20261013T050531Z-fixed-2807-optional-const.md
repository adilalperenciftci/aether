- **A `const` can have an optional type.** `const LIMIT: int? = 3` gave its
  `static const ae_opt_int` the bare value, which gcc rejected, and `const
  NO_LABEL: string? = none` was refused as not a constant. The constant
  takes the optional's own value now (`{ .has = 1, .val = 3 }`, `{0}` for
  `none`) and reads, `??` and `match` work on it (#2807).
