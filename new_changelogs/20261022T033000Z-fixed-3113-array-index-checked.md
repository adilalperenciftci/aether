- **An index into a fixed-size array is checked, as a slice's is.**
  `a[i]` on a `T[N]` compiled to a plain C `a[i]`, so `a[4] = 99` on an
  `int[3]` wrote into the stack frame and a read past the end returned
  garbage, with no panic. Every index into a `T[N]` (a read, a store, `+=`,
  `++`, through a local, a field, a parameter, an actor's state or a
  `const` table) is now checked against N, and one outside `0 ..< N` is the
  slice's panic: `array index 4 out of range for length 3`, with the source
  line, which `try` catches. An index known when the program is compiled
  that is out of range is a compile error. With a constant N and a loop
  bounded by it the C compiler drops the test: the cryptography modules'
  table lookups and the cross-language benchmarks run as fast as before
  (#3113).
