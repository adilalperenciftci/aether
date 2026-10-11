- **A local named after the function its own initializer calls builds and
  runs, wherever the code sits.** `helper = helper() + 1` used to get three
  answers: `ae check` of the module on its own passed; in a main file gcc
  failed with "called object 'helper' is not a function", because a C
  declaration is in scope in its own initializer; and a program importing
  the module failed with E0301 "Undefined function 'helper'", because the
  merge left the call unrenamed. A local's scope starts after its
  initializer, so the call is the function's and every later `helper` the
  local's; the generated C names such a local apart (`ae_local_helper`), the
  merge renames the calls that come before the binding, and a local that
  both arms of an `if` bind no longer hides the function from its own
  initializer in the checker. Calling the function by that name after the
  binding is an E0301 that says the local hides it, instead of "Undefined
  function" (#2683).
