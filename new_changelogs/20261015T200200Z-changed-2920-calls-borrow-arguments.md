- **Every call borrows its arguments.** A fresh value passed to a function,
  a closure, a function pointer or an extern is released after the call;
  a callee that keeps or returns one takes a reference of its own (R3). The
  compiler no longer reads a callee's body, or every closure in the
  program, to decide it. An extern that keeps what it is given declares the
  parameter `@retain` (R4): the call then hands it a reference, as it now
  does for a closure (#2920).
- **`@retain` on the std externs that keep a closure.** `observe`, the
  worker pool's jobs and main-thread poster, the http and net server route
  handlers, and the QuickJS function binding keep the closure they are
  given; their declarations now say so (#2920).
- **A closure in a `ptr` slot is the program's to give back.** A `ptr`
  slot owns nothing: `box_closure(f)`, or a closure stored into a `ptr`,
  makes a box holding a reference of its own, which `release_closure(p)`
  gives back. A borrowing `ptr` parameter gets a box on the caller's stack
  instead, so passing a closure to one allocates nothing (#2926).
- **A failed `list.set` gives back the value it was handed.** An index out
  of range kept the string or closure box the store had taken (#2922).
