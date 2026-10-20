- **A clause set returns the join of its clauses' results.** A function
  written as several clauses took the result of its first clause with a
  known type, so a later clause's wider value was cut to it with no word:
  `pick(0, s: int, b: long) -> s` with `pick(k, s: int, b: long) -> b`
  returned 705032704 for 5000000000. Its result is now the join of every
  clause's, as an if-expression's arms join (a long, a float, an f32 or a
  uint32 beside an int is that type). A type written on a clause is the
  set's and an inferred clause must fit it, and two results that do not
  join (an int and a string) are E0200 naming both (#3061).
