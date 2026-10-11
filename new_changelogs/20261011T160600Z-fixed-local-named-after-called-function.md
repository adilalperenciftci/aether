- **A local named after the function its own initializer calls gets one
  error, wherever the code sits.** `helper = helper() + 1` used to get three
  answers: `ae check` of the module on its own passed; in a main file the
  checker passed and gcc failed with "called object 'helper' is not a
  function", because a C declaration is in scope in its own initializer; and
  a program importing the module failed with E0301 "Undefined function
  'helper'", which points away from the cause. All three now report E0400 at
  the call, naming the local and the function, with a hint to rename the
  local (#2683).
