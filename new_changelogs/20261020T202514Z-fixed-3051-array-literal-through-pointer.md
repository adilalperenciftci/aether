- **An array literal of fields read through a pointer has their type.**
  `arr = [b.inner, b.inner]` with `b = heap.new(Outer)` was taken for an
  int array, and the C compiler refused `int arr[2] = {b->inner, ...}`;
  so were literals of string and pointer fields read that way. A literal
  whose elements agree on a type is an array of that type once they are
  checked, where the early guess had defaulted it to int; a type the
  place gives the literal still stands (#3051).
