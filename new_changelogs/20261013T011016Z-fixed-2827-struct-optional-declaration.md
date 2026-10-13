- **`Point? q = ...` declares a struct's optional.** The C-style typed
  declaration took `Point p`, `Pair[8] ps` and `mod.Type t` as declarations,
  but not a struct's optional: `Point? q = match n { ... }` and `Point? r =
  Point { x: 7 }` were "unexpected `?` in expression", the `?` read as the
  ask operator. A name, `?`, a second name and `=` on one line now declare
  one. Without the `=` the line is still an ask, as `d ? GetCount` is (an
  ask whose message has no braces, or has them on the next line), whatever
  the first name also names; a struct's optional with no value is spelled
  `let r: Point? = none` (#2827).
