- **A function of one clause can take a string literal pattern.**
  `only_hi("hi") -> int { ... }` emitted the literal into the C as a bare
  identifier, so the program did not compile ("'hi' undeclared"). Its
  check compares by content now, NULL-safe, as a clause set's dispatcher
  does (#2467), so a counted string with the same characters matches
  (#2913).
