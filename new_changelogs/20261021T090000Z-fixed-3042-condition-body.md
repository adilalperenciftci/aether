- **A condition's own error no longer hides its body's errors.** In 0.836.0
  a condition that reported its own error was not also called not boolean,
  but the whole `if`, `while` or `for` was then skipped, so an error in its
  body went unreported. The body is checked now; "For loop condition must
  be boolean" is reported at the condition rather than at 0:0; and an
  optional used bare as a condition gives one error, with the hint
  `o != none`, and its `if` branch is checked narrowed (#3042).
