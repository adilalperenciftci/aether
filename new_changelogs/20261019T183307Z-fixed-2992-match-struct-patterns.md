- **A match arm matches a struct by its fields.** `match a { Pt { x: 0, y: _ }
  -> 1 }` was read as a struct literal, so its `_` was "Undefined variable
  '_'" and a name in it bound nothing. An arm takes the struct pattern a
  clause head takes (#2988), through the same checks, test and bindings: a
  literal field must be equal (a string by content), `_` takes any value, a
  name is bound to its field, and a struct pattern over a field matches that
  field; the value matched must be that struct. A pattern with a literal
  field takes only some values, so a match of such arms without `_` may run
  no arm (a function returning from each still reaches its end), while one
  ending in a pattern that tests no field covers its struct. A struct a call
  returns, matched, is dropped when the match ends (#2992).
