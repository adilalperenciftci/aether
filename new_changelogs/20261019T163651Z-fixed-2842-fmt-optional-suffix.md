- **`ae fmt` closes a closure's parameters after an optional as after any
  type.** `|o: int?|` came out as `| o: int?|` while `|s: Shape|` became
  `| s: Shape |`: the formatter kept the author's spacing on both sides of
  every `?`, which is also the actor ask. A `?` written tight after a name
  or a `)` is a type's optional suffix, and the token after it is now spaced
  as it would be after the type, so the closing `|` takes its space. Two
  tests in the tree are reformatted (#2842).
