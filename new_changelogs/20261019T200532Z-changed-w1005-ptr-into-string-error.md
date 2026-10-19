- **A bare `ptr` given to a `string` local is an error now, E0202 (was the
  warning W1005).** `s = map_get_raw(m, k)`, or a tuple slot,
  `name, err = map.get(m, k)`, would read the pointer as text whatever it
  points at (a list, a struct, bytes with no end); `ae check` and `ae build`
  refuse it, naming the typed form: `map.get_string`, `list.get_string` or
  `string.from_ptr`. W1005 warned in 0.830.0 and 0.831.0 while the Aether
  family moved off it (ae3d, aeb, aether-ui, aephysics, sae, aeo, selaenium,
  and std and contrib here). `null`, a `string.*` result typed `ptr`, the
  accessors themselves, and a local whose first binding is the `ptr` compile
  as before. tests/regression/test_destructure_reassign_over_heap_lhs.ae
  reads its maps with `map.get_string`.
- **`ae check std/bytes/module.ae` passes again.** std.bytes imported
  std.string without using it, so checked on its own its `string_from_ptr`
  collided (E1001) with 0.830's `string.from_ptr`; the import is gone.
  `bytes.string_from_ptr` is unchanged.
