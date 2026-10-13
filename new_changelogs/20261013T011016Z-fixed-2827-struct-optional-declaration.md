- **`Point? q = ...` declares a struct's optional.** The C-style typed
  declaration took `Point p`, `Pair[8] ps` and `mod.Type t` as declarations,
  but not a struct's optional: `Point? q = match n { ... }` and `Point? r =
  Point { x: 7 }` were "unexpected `?` in expression", the `?` read as the
  ask operator. A type name, `?` and a binding name followed by `=`, `;` or
  the end of the line now declares one; an ask has its message's `{` there
  (#2827).
