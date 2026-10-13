- **A tuple literal can become an optional.** `let t: (int, int)? = (3, 4)`
  stored `34` (its elements' text run together) and printed `34 0`, the
  same in an `(int, int)?` struct field's literal or store, and `(s, 1)`
  became the undeclared name `s1`. The literal is the tuple's compound
  literal inside the optional now, each element cast to its slot's type
  (#2833).
