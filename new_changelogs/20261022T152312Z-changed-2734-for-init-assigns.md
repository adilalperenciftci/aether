- **A C-style `for` loop's bare init assigns a variable already bound.**
  `i = 5; for (i = 0; i < 3; i++) {}` left `i` at 5: the loop declared a new
  `i` that shadowed the local. A bare init (`i = 0`) is now the binding it
  is anywhere else: it assigns a local, a module-level `var` or an actor's
  state field of that name, which keeps the value the loop ends with, and
  declares the loop's own variable only for a new name. A typed init
  (`int i = 0`) and a range-for's variable still declare the loop's own.
  To keep a loop that relied on the shadowing, give its variable a new name
  or write its type in the init (`for (int i = 0; ...)`) (#2734).
