- **`[10, 20, 30][i]` indexes an array literal in place.** The literal was
  emitted as the bare initializer `{10, 20, 30}[...]`, which C refuses, so
  indexing a literal as an initializer, argument, return value or operand
  failed to build. The literal is now the statement's temporary, as one
  passed as an argument is (a string or struct literal's elements are owned
  and dropped with its block), or a compound literal where no temporary can
  be declared. The index is bounds-checked as any array index is, and
  `[..].len` on a literal is its element count.
