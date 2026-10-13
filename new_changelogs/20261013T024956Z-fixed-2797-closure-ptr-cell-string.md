- **A closure can store a string into an outer `ptr` local.** `q, n =
  names(p)` or `r = s` in a closure, where `q` and `r` are `ptr` locals the
  closure writes, handed the `ptr` cell to the string cell setter, and gcc
  rejected the C. The store follows the cell's type, so a `ptr` cell, which
  owns no string, stores the string as the pointer it is (#2797).
