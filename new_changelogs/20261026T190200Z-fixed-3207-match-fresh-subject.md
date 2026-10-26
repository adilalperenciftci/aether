- **A `match` or a `switch` on a fresh string frees it.** `match f() {
  "a" -> ... }` kept f()'s string in the match's subject and nothing freed
  it, whichever way the match ended. It is freed now on every exit: falling
  through, a `return` from an arm, a `break` out of a case, a nested match
  (#3207).
