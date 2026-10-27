- **Use after free, double free and dead views are compile errors.** A
  local freed on every path that reaches a later use is E0903 there: a read
  after `heap.free(n)`, a second `free(p)`, a free a loop repeats on its next
  turn without binding the local afresh, and a read of a view (a slice
  `buf[1..3]`, a cast `p as *Node`, `bytes.view(b)`) after its storage was
  freed or after a call that may move it (`bytes.set`, `bytes.copy_from_*`).
  Only a fault that happens on every path is reported. What a call does is
  read from its declaration: a `ptr`, `*T` or slice parameter declared
  `@frees` frees what it is given and one declared `@moves` may move its
  storage; C's `free` and `heap.free` free theirs. std's release functions
  declare `@frees`, std.bytes' growing calls `@moves` and its views `@into`,
  and an Aether function's declaration is checked against its body (E0904).
  The check found a freed snapshot read on a test's failure path (#1300).
