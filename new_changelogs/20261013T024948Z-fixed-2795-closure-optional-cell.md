- **An optional a closure writes is a cell.** `let a: int? = 3` followed by
  `set = || { a = 5 }` did not compile: the optional declaration path
  declared and stored a plain `ae_opt_int`, so the closure's capture of
  the cell was handed a value. The first binding makes the cell now and
  every store goes through it, a bare value wrapped, whether by `a = v` or
  a destructure slot. A `string?` cell owns its string, as a string cell
  does: a store takes a string of its own and gives back the one it held,
  a `string?` parameter's cell takes one of its own on entry, and the
  cell's last release gives back the last. What a local takes out of it
  (`v = a ?? ""`, `v = a!`, a `some(v)` binding) is a copy of its own, as
  what it takes out of a string cell is, so it outlives the next store
  (#2795).
