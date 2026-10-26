- **`free` of a `make([]T, n)` buffer gives back what its elements hold.**
  A store into an element takes a reference, but the free released only the
  buffer, so every string, closure or string-holding struct stored into
  one leaked (`xs = make([]string, 2); xs[0] = "built ${n}"; free(xs)` grew
  the heap each time). A `make` buffer is now marked, and its free releases
  each element first; a view of C memory, whose elements take nothing,
  frees only the memory, and freeing a sub-slice is still refused (#3159).
