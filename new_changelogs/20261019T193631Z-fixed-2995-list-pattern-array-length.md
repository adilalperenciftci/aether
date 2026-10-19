- **A list pattern matches a fixed-size array by its length.** `xs = [9,
  1]; match xs { [h | t] -> h  [] -> 0 }` failed in C ("'xs_len'
  undeclared"): the match read the length from a `<name>_len` local for
  every subject but a slice or a `*StringSeq`. A `T[N]` is matched by its
  length N, a slice by the one it carries, and only a bare pointer (a local
  bound to `[]` alone) takes the documented `<name>_len`. A cons pattern's
  tail is a slice whose length is `t.len`, and no longer comes with a
  `<tail>_len` local that hid one of the program's. A `_len` local beside a
  fixed-size array is now a local nothing reads, reported unused (#2995).
