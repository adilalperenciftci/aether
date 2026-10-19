- **A struct pattern in a clause head is tested and binds its names.**
  `kind(Pt { x: 0, y: _ })` matched every call, since the pattern was
  parsed and then never read: no field was tested, and a name in it
  (`Pt { x: a }`) was "Undefined variable". The clause now runs when each
  literal field is equal (a string by content), `_` takes any value, a name
  is bound to its field (typed as the field, in the body and the guard), and
  a struct pattern over a field matches that field. A struct or a field the
  pattern names that does not exist, a literal of another type than its
  field, and a name bound to a fixed-size array field are errors (#2988).
