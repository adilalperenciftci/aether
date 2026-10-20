- **A sum owns what its variants own.** A sum whose variant holds a string
  or a closure had no retain or drop: every fresh sum leaked its variant's
  string or closure environment, a copy (a capture, a return, a field) was
  freed under its other holder, a closure could not write a sum it
  captured, and a closure in a receive arm could not read a sum state
  field. A sum is now a composite like a tuple or an optional: its
  generated retain and drop are those of the variant its tag names, and
  every place (a local, a field, an element, a tuple slot, an optional, a
  capture and a cell, actor state, a message field, a parameter, a
  temporary, a return) takes, copies and drops it through them (#3005).
