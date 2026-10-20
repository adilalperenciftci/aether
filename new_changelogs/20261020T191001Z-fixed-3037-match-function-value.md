- **A value `match` over named functions is a function value.** `f =
  match k { 0 -> a  _ -> b }` left the arms bare names, so the match had
  no type: `f(3)` was E0301 "Undefined function 'f'" and `call(f, 3)`
  passed the checker and failed in the C compiler. An arm that names a
  function now gives the function as a value, as an if-expression's branch
  does: the match is of the function's type, joined with the other arms'
  (their `@keep` and `@into` modes included), and arms of two signatures
  are refused as any arms of two types are (#3037).
