- **A name first bound in a `switch` case and read after the switch is one
  variable, as one bound in an `if` branch is.** The type checker took the
  cases for part of the enclosing scope, so `switch x { case 1: v = 10 ...
  }` then `return v` passed it and failed in the C compiler ("'v'
  undeclared"), since each case is a C block of its own. Each case is now a
  scope of its own in the checker too, and the rules that let an `if`
  branch's binding outlive the `if` apply to a switch's cases: read after a
  switch at the top of the function body, bound in a `while` body, or bound
  by every case of a switch with a `default`, it is declared ahead; any other
  read after the switch is `Undefined variable` (#2732).
