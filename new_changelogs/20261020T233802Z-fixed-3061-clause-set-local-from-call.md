- **A local bound from a call of a clause set has the set's result.** The
  set's result is the join of its clauses' (#3061), but a call was typed
  by the first clause's before the set was settled, and a local bound from
  it kept that: `x = f32mix(1, h)` printed 1 while the call printed 1.5.
  The set is settled before its calls are typed, so the local, and one made
  from it, has the joined type (#3061).
