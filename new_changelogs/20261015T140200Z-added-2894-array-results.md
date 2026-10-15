- **A function returns a fixed-size array** (`-> int[2]`, `-> (Doc[2],
  int)`), returned in a struct of its own since C has no array results. A
  binding moves the elements out, a struct field or a tuple position takes
  them, and `pair()[1]` or `sum(pair())` holds the result until the
  statement is done. A closure, an extern and a function type still return
  none (E0201) (#2894).
- **An optional struct field may hold a string, a closure, or a struct or
  tuple that owns one** (`label: string?`); it owns what it holds as any
  field does (#2822).
