- **A bare enum member works as a `match` arm's or an `if` branch's value.**
  Where a value's expected type is an enum (a return, a typed binding, an
  argument, an assignment), a member may be written bare; a `match` or an
  `if` in that place now passes the enum to each arm, so `return match d {
  N -> S ... }` and `return if c { N } else { E }` no longer report
  "Undefined variable" for every arm value. An arm whose pattern binds the
  name keeps its binding (#3156).
