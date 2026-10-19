- **An optional of an enum or a distinct type binds everywhere (#2831).**
  `let a: Color? = Color.Blue` and the store `b.c = Color.Red` were refused
  ("Type mismatch in variable initialization") while a struct literal's
  field took the same value; a distinct type's optional (`Meters?`) was
  refused the same way. The checker's enum and distinct rules decided
  before its optional rule was reached. The optional rule now comes first
  and leaves the inner types to them, so a local, a parameter, a field, a
  literal, a store, a return, `??` and `match` all take one.
