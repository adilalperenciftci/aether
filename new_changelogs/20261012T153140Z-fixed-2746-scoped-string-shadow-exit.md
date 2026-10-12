- **A `return` from a block whose string shadows a local frees both.** A
  C-style `for` loop's string variable (#2742), an owning `catch` binding
  (#2333) and the `some(v)` binding of a match over a `string?` (#2750)
  each live for one block and may shadow a local of their name. Both exit
  frees were keyed by the name, so a `return` from inside the block freed
  the block's value and then tested the block's flag again for the outer
  local, whose value leaked. Such a binding is now renamed, with every use
  inside its construct, to a name of its own before code is generated, so
  each exit free reaches its own variable (#2746).
