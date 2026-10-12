- **A receive arm frees the strings its locals hold.** A string a receive
  arm built into a local (`msg = string.concat(w, "!")`) was never freed:
  the handler declared the local's ownership flag but ran neither the
  escape walk nor the exit frees a function body gets, so every message
  that ran the arm leaked the string, and a pattern binding rebound to a
  heap string (`w = string.concat(w, x)`) leaked the same way. A `string?`
  or `*StringSeq` local of an arm was not tracked at all. An arm, and the
  `after` arm of a `receive`, now run the same passes as a function body.
  A store of such a local into a string state field (`label = msg`) gives
  the state a string of its own: the local's buffer on the local's last
  use (its flag cleared), a copy otherwise. The state used to take the
  pointer while the local kept its flag set, and two state fields stored
  from one local both owned the same buffer, which was freed twice
  (#2748).
