- **A clause set of `none` and a clause that only calls the set again says
  it has no type.** `last(0) -> none` beside `last(k) -> last(k - 1)` was
  never settled, and only `last(3) ?? -1` was refused, as no optional. A
  clause that only calls its set gives the set's result and no type of its
  own now, so this set is the error a set of only `none` clauses is,
  naming the missing `T`; beside a clause that gives one, the set is its
  optional, as before (#3063).
