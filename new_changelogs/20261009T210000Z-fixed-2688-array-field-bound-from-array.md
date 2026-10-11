- **A fixed-size array field can be bound from an array.** A struct literal
  given an array (`Shelf { names: arr }`), a store of one into the field
  (`s.names = arr`, `s.names = [...]`) and the same store into an actor's
  array state field (`names = arr`) emitted C that did not compile, since C
  neither initialises nor assigns an array from an array. The elements are
  copied one by one, each taken as the field keeps it: a `string[N]` field
  takes a reference to each element of another array and a copy of each
  element of a literal, a `fn[N]` field a reference to each closure, and an
  array of structs that own strings a value of its own per element, an
  actor's array state field of such structs included (it owns its
  elements, released by its `destroy_state`); a store takes every new
  element before storing any, so `s.names = [s.names[1], s.names[0]]`
  swaps, and gives back each element it replaces. The source must have the
  field's length: another length, an array literal longer than the field,
  or a slice or pointer, whose length is not known before the program
  runs, is a type error (a shorter literal zeroes the rest). Also fixed on
  the way: a store into a string field of an element of an array of
  structs (`items[i].name = v`) was a plain store, so a literal stored over
  an owned string was freed with the array (a crash) and a fresh string
  leaked (#2688).
