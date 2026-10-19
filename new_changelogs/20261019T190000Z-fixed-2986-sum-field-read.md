- **A variant's field is read only where a match narrows the sum
  (#2986).** `s.r` with `s: Shape` outside a match, or `h.sh.r` in an arm
  of `match h.sh`, passed the checker and failed in C ("'Shape' has no
  member named 'r'"): a `match` narrows a plain variable it matches on, and
  nothing else. Such a read is now refused, naming the sum and the field,
  and the help says to bind the value to a local and match on that.
