- **`string.new_with_length(s, n)` of an Aether string copies its
  characters, and a buffer is copied as given.** Its `data` is a `ptr`: a
  buffer C filled is copied byte for byte and never read as a string, and a
  `string` argument is passed as its characters, so `n` must not exceed its
  length (`string.substring(s, 0, n)` stops at the end). It copied a counted
  or pinned string's header bytes instead of its text, and the first fix,
  which read any argument that began with a string header's magic as a
  string, followed a forged header in a binary payload (#3030).
