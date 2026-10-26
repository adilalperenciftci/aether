- **A `try` where a value goes is one error, and `ae help` leaves out the
  parser errors its findings explain.** `r = try { work() } catch e { ... }`
  was "'try' is a reserved keyword and cannot be used as an identifier",
  after which the try block's `}` closed the function and its `catch` was
  read at top level: six errors. It is now one E0100, "`try` is a statement
  and gives no value", with the statement form as its help, and the whole
  try statement is stepped over; `return try { ... }` on one line says the
  same. `ae help` on a DSL block written in YAML or HCL shape reported its
  two findings beside the two raw syntax errors they explain; the syntax
  errors from the first such finding's line on are now left out, and one on
  an earlier line stays. The reference documents `panic`, `try` and `catch`
  (#3150).
