- **An optional compares with a bare value (#2829).** `lo == 3` with `lo:
  int?`, or `b.v == 3` with a field `v: int?`, passed the type checker and
  failed in C ("invalid operands to binary =="). It now compares as the
  value wrapped into the optional, as a binding wraps it: equal when the
  optional is present with an equal value, a `string?` by its contents.
  Both operands are evaluated, in source order. A value the optional cannot
  hold, or an optional of another inner type (`int?` against a `string` or
  a `string?`), is refused at the comparison.
