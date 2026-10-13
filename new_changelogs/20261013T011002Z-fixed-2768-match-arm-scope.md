- **A name a `match` arm binds is one variable after the match, as one an
  `if` branch or a `switch` case binds is.** The language reference says a
  name first bound inside a branch and used after it is one variable for the
  whole function, and the shared hoists made that true of `if` and `switch`
  but not of `match`: `match x { 1 -> { v = 10 } _ -> { v = 20 } }` then
  `return v` was "Undefined variable". A match arm's body now joins the same
  hoists, in the checker and in codegen alike: a name read after a match at
  the top of the function body, bound in a `while` body, or bound by every
  arm of a match that runs an arm for every value (a `_` arm, or arms that
  cover its type) is declared ahead of it. A match whose value is used keeps
  its arms' names in the arms, a name an arm's pattern binds (`some(v)`,
  `[h | t]`) is that arm's own and is hoisted out of the match by no rule,
  and any other read after the match is still `Undefined variable` (#2768).
  As in an `if` branch, a closure made in a match arm inside a `while` that
  changes a variable the arm binds now changes the one variable the loop
  declares ahead of it, so closures made on different passes share it (each
  had its own before).
- **A match pattern's variable can be bound again in its arm.** `some(v) ->
  { v = v * 10 }` and `[h | t] -> { h = h * 2 }` failed in the C compiler
  ("redefinition of 'v'"), as did an if/else in the arm binding `v` in both
  branches: codegen declared the binding without recording it, so the arm's
  binding declared it a second time. The binding is now a local of the arm,
  and `v = ...` there rebinds it (#2793).
