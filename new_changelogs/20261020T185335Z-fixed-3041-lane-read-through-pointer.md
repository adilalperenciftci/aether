- **A lane read through a pointer compiles.** `b.inner.v.z`, with `b`
  from `heap.new` (or any pointer to a struct on the way), reached the C
  compiler as `b.inner.v` and stopped at "'b' is a pointer; did you mean to
  use '->'?"; through a value struct it worked. The checker now checks a
  lane read's object as it does any other member access's, so every access
  under it lowers with `->` where its object is a pointer, for reads and
  writes of four-, two- and eight-lane values (#3041).
