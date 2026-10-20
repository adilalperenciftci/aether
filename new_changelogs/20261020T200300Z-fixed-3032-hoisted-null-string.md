- **A local bound `null` in one branch and a string in another is a
  string.** Hoisted out of the branches, it took the type of its first
  binding, a `ptr`, though the same two bindings in one block make a string:
  codegen declared it `void*` and managed it as a string, and a `string`
  local could not take it (E0202). A `null` binding has no type of its own,
  so a hoisted local whose bindings are `null` and strings is a `string`
  (#3032).
