- **`free(xs)` of a slice is the builtin release whatever extern `free` a
  program declares.** A program with `extern free(p: ptr)` turned every
  `free` of a slice, in its own code and in the modules it imports, into C's
  free of the slice's pointer, while slice ownership still released the
  buffer at scope exit: a double free (ML-KEM's matrix, in a TLS test that
  declared it), and an element's references never given back. A slice
  given to an extern `free` that takes a pointer is now released by the
  builtin, as a module's own `free` already left it, so the same
  ownership checks apply: freeing a slice parameter the function only
  borrows, or a view of another slice, is a compile error there too (#3116,
  #3450).
