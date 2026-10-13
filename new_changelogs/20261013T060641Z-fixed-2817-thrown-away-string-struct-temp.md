- **A thrown-away string made from a field of a struct a call returns no
  longer leaks the struct.** `string.concat(item(2).label, "e")` on a line
  of its own freed the string it made but never destroyed the struct
  `item(2)` returned, so that struct's strings leaked once per statement;
  the statement now keeps such structs in temporaries and destroys them, as
  it already did for any other value it throws away (#2817).
