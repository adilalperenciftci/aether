- **An `if` expression passed as an argument gives back what its branch
  made.** `show(if c { "${k}" } else { "${k}!" })` leaked the string the
  branch made, and the same with a branch making a closure or a struct
  literal; an `if` giving arrays as an argument did not compile. A branch's
  fresh value is a fresh argument, as a call's result is: the call's
  temporary takes each branch (a fresh value moved in, any other retained
  or copied) and is released after the call. An `if` giving arrays fills
  a temporary array from the branch it takes (#3006).
