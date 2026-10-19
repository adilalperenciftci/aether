- **A copy of a narrowed value has the narrowed type (#2848).** `t = s` in
  the `Circle` arm of a match on a `Shape`, then `t.r`, passed the checker
  and failed in C ("'Shape' has no member named 'r'"): the declaration
  kept the scrutinee's type from the early inference pass while the
  checker read `t` as the Circle. A copy of a none-checked optional
  (`v = o` inside `if o != none`) was refused for `v + 1` the same way. The
  first binding of a name now takes the narrowed value's type: `t` is a
  Circle, `v` an `int`.
