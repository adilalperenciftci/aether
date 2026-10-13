- **`Point? q = ...` declares a struct's optional.** The C-style typed
  declaration took `Point p`, `Pair[8] ps` and `mod.Type t` as declarations,
  but not a struct's optional: `Point? q = match n { ... }` and `Point? r =
  Point { x: 7 }` were "unexpected `?` in expression", the `?` read as the
  ask operator. A name, `?` and a second name on one line now declare one
  when `=` follows, or when the first name is a type (a struct, union,
  enum, sum, distinct type, bitstruct, `cfn`, message or builtin type the
  name spells). Otherwise the line is still an ask, so `d ? GetCount`, an
  ask whose message has no braces or has them on the next line, is one
  (#2827).
