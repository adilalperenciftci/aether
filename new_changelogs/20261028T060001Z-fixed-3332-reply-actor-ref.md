- **A reply of an actor reference keeps its type.** `reply w`, where `w` is
  an `actor_ref`, was sent as an `int` (the pointer cut to its low half),
  and the ask's result typed `int`, so a send through it did not compile.
  Both sides now carry it as a pointer, bare or as a reply message's field
  (#3332).
