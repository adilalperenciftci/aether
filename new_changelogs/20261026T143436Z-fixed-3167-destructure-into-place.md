- **A destructure stores into an element or a field.** `names[0], _ =
  pair()` and `p.name, p.n = pair()` were "Expected statement in block".
  A slot is a name, `_`, an element or a field; a place takes its value as
  `place = value` stores it, ownership included (#3167).
