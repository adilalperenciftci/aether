- **`exit(f(s))` reads `s` before the scope releases it.** A call to `exit`
  drains the function's pending releases first, since nothing runs after
  it, and that drain was emitted ahead of the argument, so `f` got the
  freed string local as NULL (`exit(check(file))` saw `(null)`,
  `exit(string.length(s))` exited 0). It came in with 0.818.0, when a
  string local started owning its value. The exit status is now evaluated
  into a temporary, then the scope is drained, then the process exits,
  which is the order `return f(s)` uses. Found by aeci.
