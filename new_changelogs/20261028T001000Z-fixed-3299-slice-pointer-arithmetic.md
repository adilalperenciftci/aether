- **`s + n` on a slice points at element `n`.** A slice decays to its
  pointer in arithmetic, and that pointer was arithmetic on a bare `ptr`,
  which counts bytes: `b + 3` on a `uint32[]` pointed into the first
  element, so a write through it landed at byte 3. It now points at element
  `n`, as the language reference says and as it does for a `T[N]` array; a
  bare `ptr` still counts bytes, and so does a difference of a `ptr` and a
  slice (#3299).
