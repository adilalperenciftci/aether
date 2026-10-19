- **A value that branches has a type for every kind of branch.** An `if`
  expression's branches and a value `match`'s arms join by one rule
  (branch_join_type): beside numbers, an optional and its value, and a sum
  and its variant, two variants of one sum are the sum, each branch wrapped
  into it (#2996); fixed-size arrays of one element type and length are that
  type, declared and filled as an array (#3004); tuples join position by
  position, and a tuple literal is the tuple of its elements' types wherever
  it stands, so `t = (5, "z")` destructures and a tuple literal passed
  through a fn pointer is a temporary its call drops (#3003). The joins hold
  bound, returned and as an operand, and a local's annotation or the result
  type picks the sum when two sums share the variants. Branches of no one type
  (arrays of another length or element type, tuples of another shape) are
  refused naming both types, as two unrelated types were.
