- **Whether a function returns nothing no longer depends on the order the
  functions are defined in.** With `f(x) -> { g(x) }` defined before
  `g(x) -> { note(x) }` and `note` returning nothing, `f` was checked while
  `g` still held its own `return note(x)`, so `f` returned `g`'s void and the
  C compiler stopped ("void value not ignored"); in the order note, g, f it
  worked. A closure `|x: int| -> g(x)` with `g` defined after `main` failed
  the same way. Which of the program's functions return a value is now
  settled before any body is checked, over the calls their `return`s make,
  and a call of a closure that returns nothing counts as one of a function
  that does (#2736).
