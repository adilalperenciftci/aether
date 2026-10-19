- **A call through an erased `fn` coerces its arguments (#2847).** A bare
  `fn` has no parameter types, so `call(f, 5)` into `|o: int?|` handed the
  closure an int where it read an optional (it saw 0), a Circle into
  `|o: Shape?|` crashed, and an int into `|x: float|` read 0.0, through a
  `fn` parameter, a field or a returned closure. The function a closure
  value points at has the parameter types, so the call now compares it
  with each closure literal and function value of the program whose
  parameters take these arguments only coerced, and calls the one it is
  through its own signature, the arguments wrapped or converted as a
  direct call's are.
