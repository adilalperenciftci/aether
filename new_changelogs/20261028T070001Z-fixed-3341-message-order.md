- **A message is known to every actor and function, wherever it is
  declared.** Codegen emitted a message, and gave it the id its sends and
  receive arms use, only when it reached it in the program. An actor declared
  before a message it handled dropped that message without a word (the arm
  never ran). A function that sent a message declared after it, with an
  actor between them, did not compile. And a program's own actor could not
  handle a message an imported module exports, because the merge puts the
  module's declarations before `main`. Messages are now emitted ahead of the
  actors and functions, as structs already were (#3341).
