- **Every string place takes a reference of its own, and shared ones count
  atomically.** A store into a module `var`, a struct field (any path, and a
  struct literal), an actor's state field or a container element (`list.add`,
  `list.set`, `map.put` of any `string`) takes the value: a fresh one moved,
  any other retained, a literal handed over as it is. The store releases the
  value it replaces; a module `var` used to keep every value it ever held.
  A string stored where another thread can read it (a module `var`, a
  closure's capture or cell, a container, a field behind a pointer) is
  published, so its count is atomic (#2919). `string.free(g)` on a module
  `var` releases it and leaves it empty. A list owns the strings it was
  given: freeing them by hand as well is a double free (#2920).
