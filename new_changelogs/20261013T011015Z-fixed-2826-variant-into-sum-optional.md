- **A variant put into a sum's optional is wrapped into the sum.** Returned
  from a `-> Shape?` function, bound to a `Shape?` local or passed to a
  `Shape?` parameter, a `Circle { ... }` was written as the optional's value
  as it was, and the C compiler refused it ("incompatible types when
  initializing type 'enum <anonymous>' using type 'Circle'"). The optional's
  wrap now wraps a variant into the sum first, as a variant into the sum
  itself is (#2826).
