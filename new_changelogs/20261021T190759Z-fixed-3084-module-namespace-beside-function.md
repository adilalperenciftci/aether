- **A module's constant reads through its namespace beside a function of
  that name.** Since 0.837.0, a program with a function `frame() -> ptr`
  that imports a module which itself imports `frame` failed in that
  module: `frame.SETS` was read as a field of the function's `ptr` result,
  "Type 'ptr' has no field 'SETS'", and so did the program's own
  `frame.SETS`. A function has no fields, so it no longer hides a
  namespace of its name; a value of the name (a local, a parameter, a
  global) still does (#3084).
