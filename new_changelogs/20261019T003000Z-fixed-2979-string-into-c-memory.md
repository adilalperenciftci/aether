- **A string stored into C memory that outlives the function is refused
  (#2979).** `(names as string[])[i] = s` gives C the characters and no
  reference. E0902 refused a string built in the statement and its help
  said to bind it to a local first, which compiled and freed the string
  when the function returned, so the array held a freed string (every
  runtime animation name in a game went to garbage, with no warning). A
  string that is not pinned stored into C memory that outlives the
  function is now E0902 too: memory reached through a parameter, a
  module-level `var`, a field or a heap box, or whose pointer is returned,
  stored, captured, sent or passed to a `@keep` parameter. The help names
  `(p as ptr[])[i] = string.keep(s)` and `string.release_kept` where the
  memory is freed. Memory the function allocates and does not let escape
  (an argv array handed to C) still takes a local, and a literal or a
  `const` bound to one goes into either.
