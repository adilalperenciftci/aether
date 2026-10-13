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
  its arms' names in the arms, and any other read after the match is still
  `Undefined variable` (#2768).
