- **A `match` arm and a `switch` case are checked against the value they
  compare.** Nothing checked an arm's pattern against the value matched, so
  the C compiler met the mistakes: an arm naming no variable (`other ->`) was
  "'other' undeclared" at a misplaced line, a string arm over an `int`
  compared a pointer with an integer and never ran, a literal arm over an
  optional or a sum was dropped without a word, and `none`, `some(v)`, a list
  pattern or a range over a value they cannot match failed in C. Each is now
  an error at the arm, saying what the arm compares and how to write it, and
  a `switch` case is checked the same way. A comma-list of bare enum members
  (`Red, Green ->`) and a bare member in a `switch` case now name the
  members, where they were undeclared names in C; a `switch` over a string or
  a float compares by content or value, where it was a C `switch` on a
  pointer; and a `uint64` or `uint32` value is matched as itself, where it was
  cut to an `int` (5000000000 took the arm for 705032704) (#2727).
