- **A function that indexes its slice parameters runs a view body when it
  is given views.** Called where the C compiler cannot see the argument's
  origin (another file, a function value, a library boundary), every index
  of a `T[]` parameter tested for an unbounded view (`p as T[]`) and then
  the bound, and the loop around it did not vectorize. Such a function now
  has two bodies: one test at entry calls a view body, which indexes with
  no test, when every slice parameter it indexes is a view, and the
  function's own checked body runs otherwise. A bounded slice is checked
  as before and still panics out of bounds. Measured with the origin
  hidden, ps per element at -O3: an f32 map over views 302 to 53, an int
  sum 194 to 83; bounded slices unchanged. A slice the function binds
  again, takes the address of, or that a closure in it captures, is not
  versioned (#3029).
