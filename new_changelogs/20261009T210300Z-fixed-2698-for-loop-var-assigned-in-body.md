- **A C-style `for` body that assigns the loop variable assigns it.** In
  `for (i = 0; i < 3; ) { i = i + 1 }` the assignment declared a new `int i`
  in the body, initialised from itself, that shadowed the loop's, so the loop
  never ended; with an increment as well, the body read an uninitialised
  value. The variable the init binds is now the loop's in the condition, the
  increment and the body (#2698).
