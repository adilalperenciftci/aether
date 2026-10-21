- **A module's body sees its own declarations and imports, not the
  program's.** A module's code resolved names the program declared: its
  `helper()` called a program's `helper()` it never imported, and a
  program's `struct frame` took the place of the module's own import in
  `frame.SETS`. A module's call of a function it does not see is refused
  now, and its `frame.SETS` is its import's constant beside any function
  or type of that name, the program's or its own: a module's own `frame()`
  no longer turns it into `user_frame.SETS` (#3088).
