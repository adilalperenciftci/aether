- **A closure can store a string into an outer `ptr` local.** `q, n =
  names(p)` or `r = s` in a closure, where `q` and `r` are `ptr` locals the
  closure writes, handed the `ptr` cell to the string cell setter, and gcc
  rejected the C. The store follows the cell's type now, and a string
  stored into a `ptr` cell reaches C as its characters, as a plain string
  stored by the cell's own scope does: the cell keeps a string of its own
  beside the pointer until the next string store or its last release, so
  the characters outlive the closure that stored them (#2797).
