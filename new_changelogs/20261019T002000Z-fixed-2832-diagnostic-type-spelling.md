- **Diagnostics spell a type as the source does (#2832).** A `fn?` was
  named `|| -> void?`, a distinct string's optional `Name?` was `string?`,
  a typed function `fn(int) -> int` was `|int| -> int` and a struct was
  `struct P`, in the messages that named a type through the display used
  by the `--emit=lib` catalog and the schema tables. Those messages (a
  destructure of a non-tuple, an optional compared with what it cannot
  hold, a function type returning a fixed-size array, a slice of another
  element type, a missing return, a local bound as two types, a struct
  defined twice) now spell the type as it is written.
