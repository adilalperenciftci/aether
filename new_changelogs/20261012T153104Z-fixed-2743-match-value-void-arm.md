- **A `match` whose value is used, with an arm that calls a function
  returning nothing, is an error at that arm.** The `match` takes its value
  from the arm that runs, and codegen stored the call's void in the result:
  the C compiler stopped with "void value not ignored". A `match` that is
  returned for its value, bound, or the value of an arm of such a `match`
  now refuses the arm, naming the call and how to give the arm a value. An
  arm that ends in a statement, such as a `return`, is accepted as before
  (#2743).
