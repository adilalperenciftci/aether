- **`append(xs, v)` grows a slice.** `xs = append(xs, v)` gives a `T[]` one
  element longer with `v` at its end, growing the buffer in place with its
  capacity doubling, so building a list of n elements costs O(n) where a
  program used to copy every element into a buffer one longer on each push
  (O(n^2), and the old buffer leaked unless it was freed by hand). It grows
  the empty slice (`[]`, `null`), a `make([]T, n)` buffer or one an earlier
  `append` gave; its elements are places, as a `make` buffer's are (a string,
  a closure or a struct that holds one is taken, and `free` releases each).
  Appending to a view (a sub-slice, an array, `string.bytes(s)`, C memory)
  is refused where the checker sees it (E0200) and a named panic elsewhere,
  as `free` of one is. The slice keeps its shape: a grown buffer is marked,
  and its capacity is the power of two that holds its length.
