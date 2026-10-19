- **Typed string accessors, and W1005 for a `ptr` given to a `string` local.**
  A `string` local re-bound to a bare `ptr` (`s = map_get_raw(m, k)`, or a
  tuple slot, `s, err = map.get(m, k)`) read the pointer as text whatever it
  pointed at, a nested list or a struct included. `map.get_string`,
  `list.get_string` and `string.from_ptr` say the value is a string and check
  it is one, returning `(null, "not a string")` when it is not, and the
  implicit form now warns (W1005), naming the accessor; a later release makes
  it an error. A `ptr` result of a `string.*` function (`string.from_int`) is
  a string already and is not warned about. The uses in std, contrib, the
  tests and the docs are moved over.
