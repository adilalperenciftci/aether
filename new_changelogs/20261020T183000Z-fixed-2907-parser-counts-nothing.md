- **A program of 10000 or more declarations compiles.** parse_program
  stopped at a 10000-pass "safety limit" whose message printed nothing, so
  aetherc exited 1 without a word. The two `when` region loops had the same
  cap, a switch stopped at 1000 cases, a match at 1000 arms, a case block
  and an actor body at 1000 statements and a postfix chain at 100, all
  silently. Every loop guarantees forward progress instead, every parser
  message is a diagnostic (an actor left open at the end of the file, a bad
  `when` condition, a stray token in a case block or a `when` region), and
  `1 -> }` in a match is E0100 at its `->`. One limit stays and is reported:
  a chain of more than 1000 operators or postfix operations on one level is
  E0100 naming it, since every pass walks such a chain recursively. aetherc
  overflowed its 2 MB Windows stack at about 600 chained `+ 1`; it now
  reserves the 8 MB a main thread has on Linux and macOS. The limits are in
  the language reference, under Compiler Errors (#2907).
