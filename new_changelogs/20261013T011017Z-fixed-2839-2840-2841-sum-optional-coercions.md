- **A variant or a bare value reaches a sum or an optional everywhere it is
  given one.** Three places passed it as it was, and the C compiler refused
  the result: a variant as the default of `??` over a `Shape?` (`e ?? Circle
  { r: 1.0 }`, "type mismatch in conditional expression", #2839), and the
  arguments of a closure call, `call(f, Circle { ... })` into `|s: Shape|`
  or `|o: Shape?|` and `call(h, 3)` or `call(h, none)` into `|o: int?|`
  ("incompatible type for argument 2", #2840). Each is now wrapped as a
  direct call's argument is. And `c2 = o2`, after `o2 = Circle { ... }` on a
  `Shape?` local, was "Type mismatch in variable initialization": the early
  pass took `c2` for the Circle last put in `o2`. The first binding of a
  name with no written type now takes the optional or sum it is given
  (#2841). A field read plainly off an optional (`c2.r`, `o2.r`, `p.x` on
  a `Point?`) was accepted and failed in C ("'ae_opt_Shape' has no member
  named 'r'"); it is now a type error naming `?.`, `!` and narrowing.
