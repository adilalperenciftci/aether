- **A store into another actor's state through its reference takes what it
  stores and releases what it replaces (#3386).** `w.label = s`,
  `w.kept = r`, `w.items[i] = r` and `w.names = arr`, with `w` an actor's
  reference, were plain C assignments (the whole-array one did not compile):
  the state shared what its source still owned, so once the source's owner
  let go the actor held released strings and closures, and released them a
  second time when it ended, and what a store replaced leaked. A part of
  such a field (`w.kept.name = s`, `w.items[i].name = s`) took the new
  value but leaked the old one. They are R3's stores now, as the actor's
  own are, and what they take is published, since the actor reads it on
  its own thread. `std.supervise.start` copied its spec's children into the
  supervisor that way before freeing the spec: a factory that captured a
  local crashed on its first call, and a child name built at run time
  dangled in `supervise.which` and in the give-up reason.
