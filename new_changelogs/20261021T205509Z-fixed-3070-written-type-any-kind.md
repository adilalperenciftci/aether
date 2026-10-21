- **A written type of any kind is the type of a local bound in several
  branches.** `x = "s"` in one branch beside `int x = 1` in the other made
  `x` a string, and the int branch stored 1 into it: the program crashed
  when that branch ran (the other order was refused). The written type is
  the local's type in either order now, and a binding of a value it does
  not hold, the string here, is a compile error at that binding (#3070).
