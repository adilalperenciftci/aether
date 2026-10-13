- **A function whose result type is a struct's optional parses.**
  `find(n: int) -> Point? { ... }` was "Expected IDENTIFIER, got
  LEFT_BRACE": the definition parser read `-> Name` as a written result
  type only when `{` followed the name (or a bracket group and then `{`),
  so the `?` sent it to the arrow-body path and left the body over. A `?`
  between the name and the body, or a `requires` / `ensures` clause, now
  marks a result type as it does after a qualified name (#2809).
