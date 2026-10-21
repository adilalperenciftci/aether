- **A write through `string.bytes(s)` is a named panic, not a crash.** The
  view of a string's bytes is read-only (a literal's are in read-only
  memory, a counted string's are shared), and nothing enforced it: `v =
  string.bytes("abc")` then `v[0] = 66` passed `ae check` and crashed
  (0xC0000005 on Windows), and on a heap string it changed text others
  hold. The view now carries a read-only mark beside its length, and a
  store through it (an element store, `+=`, `++`), or through any view made
  from it, in the function or one it is given to, panics with "a write
  through a read-only view of a string"; a store the checker can see
  through a local bound to it is E0200. Reads are zero-copy and cost what
  they did (#3025).
