- **A local bound in several branches joins as an if-expression does.** A
  name bound in two branches is one variable of the join of its bindings,
  and that join took C's usual conversions while an if-expression's
  branches take a type that holds both: `x = -1` in one branch and `x = u`
  (a `uint32`) in the other made `x` a `uint32`, and -1 printed as
  4294967295. The local is now a `long`, `x = 0` beside the `uint32` keeps
  it a `uint32`, and a signed value beside a `uint64` is the compile error a
  binding of another type in another branch is (#3064).
