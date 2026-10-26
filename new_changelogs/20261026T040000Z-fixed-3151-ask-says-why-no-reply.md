- **An ask that gets no reply says why, and an ask to a dead actor ends at
  once.** An ask to an actor that had died waited the whole timeout (5 s by
  default) and gave the reply's zero value, which a caller could not tell
  from a reply of 0, and a timed-out ask gave the same zero with no reason.
  `v, err = actor ? Msg {}` now gives the reply and `""`, or the zero value
  and `"ask timed out after N ms"`, `"the actor is dead"` or `"the actor died
  before it replied"`. In either form an ask to a dead actor returns at once,
  and so does one whose actor dies before replying: a dropped ask and the
  ask a panicking handler held wake their asker instead of leaving it to
  the timeout (#3151).
