- **A returned value is checked against the result type.** The checker
  checked what a `return` gives on its own and never asked whether it fits
  the result type, as it asks of a typed binding's value, so every mismatch
  reached the C compiler: `word(n: int) -> string { return n }` failed with
  "returning 'int' from a function with return type 'const char *'". A
  value of another kind is now E0200 at the `return`, naming both types, in
  a function, a closure and a call's trailing block, value by value in a
  multi-value return and arm by arm in an `if` or `match` returned for its
  value. The rules are a typed binding's, with what C converts: numeric
  scalars into one another, a bool to an integer and back, `T` to `T?`,
  `none`, a variant to its sum, an enum to an integer and back, `null` or an
  int to a pointer, `null` or `[]` to a slice, and a C string pointer to a
  `string` and back. With no result type written, the first `return`'s type
  is the result, and a later `return` an inferred `int` would truncate (a
  `long`, a `uint32`, a `float`) is the narrowing error an inferred `int`
  local gives. Some returns that compiled before are refused, because the
  value was converted to something it does not mean: an enum returned as a
  `string`, a pointer, a float, a byte or a bool, a bool returned as a float,
  a pointer or an enum, a pointer or a float returned as a bool, a float or
  a byte returned as an enum, a number, a bool, an enum or a typed pointer
  returned as a `string?`, and `[]` returned as an `int?`. A closure
  returned as a `ptr`, a pointer returned as a closure or a value optional,
  and `[]` returned as a scalar failed in the C compiler before and are
  refused with the fix (`box_closure`, `unbox_closure`, `none`) (#2782).
