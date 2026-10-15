- **An untyped const array whose first element is not a bare literal is an
  array of its elements' type.** `const T[] = [-1, 2, 3]` (or `[0 - 1, ...]`,
  `[~1, ...]`, `[-1.5, 2.0]`) was taken for an array of `ptr`: its first
  element had no type yet when the parser guessed, so it was emitted as
  `static const void* T[] = {...}`, which clang refuses (gcc only warned)
  and which read back as pointers (`x = T[0]` was a `void*`). The parser now
  leaves the element type unknown and marks the declaration inferred, and
  the typechecker gives it the literal's type once the elements are typed.
  Found by ae3d's shader call table (`const CALL_ARGS[] = [-1, -1, -1, 2,
  ...]`), which built with gcc and not with Apple's clang.
