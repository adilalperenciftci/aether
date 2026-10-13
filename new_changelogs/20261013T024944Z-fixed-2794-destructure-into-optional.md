- **A tuple destructure into an optional local compiles.** `let a: int? =
  none` then `a, b = two()`, or the `string?` equivalent, stored the
  slot's bare value into the `ae_opt_<T>` variable, and gcc rejected the
  C. The slot is wrapped now, as `a = 7` wraps a value, and a `string?`
  local frees the string it held and owns the new one when the call handed
  it over. The same holds for a closure's destructure that writes an outer
  optional (#2794).
