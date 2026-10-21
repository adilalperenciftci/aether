- **An array literal in an array of a sum holds its variants.** `let xs:
  Shape[2] = [c, q]` (a `Circle` and a `Square`) failed in the C compiler
  on 0.837.0 (the elements were not wrapped as `Shape`), and since the
  array-literal element check it was refused naming the wrong type: the
  place's type never reached the literal, which was an array of its first
  element's. The literal now takes the array-of-sum type of its place (a
  typed declaration, an argument, a written result, a struct field, a store
  into such an array) before it is checked, and each variant is wrapped as
  the sum (taken, when it owns a string) wherever the literal is generated.
  An array literal passed to a sized-array parameter of plain elements,
  `f([3, 4])` for `f(xs: int[2])`, which C refused as a bare `{3, 4}`, is a
  temporary of the statement too (#3071).
