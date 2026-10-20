- **E0902 follows a borrowed `ptr` into a loop's next pass.** In a loop,
  `kept = q` placed before `q = p` (or `kept = s.a` before `s.a = p`) keeps
  `p` from the second pass on, but the check walked the body once, in
  order, and let it through. A loop's body is now checked with what every
  pass through it binds, nested loops, `break` and `continue` included, so
  such a store is E0902; a loop that only reads what it stored in the same
  pass stays accepted, and so does one that binds the local anew before
  reading it (`q = list.new()`, `kept = q`, `q = p`) (#3047).
