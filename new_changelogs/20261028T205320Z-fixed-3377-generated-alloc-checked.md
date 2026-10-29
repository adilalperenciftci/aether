- **Every allocation the compiler makes for a program is checked.** The
  helpers the generated C uses for a captured variable's cell, `ref`,
  `lazy`, a closure's environment, a closure boxed into a `ptr` and
  `heap.new` used `malloc`'s result unchecked (only the cell checked it):
  out of memory, the program dereferenced NULL, a crash with no message,
  inside a library call or not. They now go through one checked
  allocation: inside a library call the call ends with
  `AETHER_OUT_OF_MEMORY`, and elsewhere it is a panic naming what ran out
  ("out of memory in heap.new"), which a `try` catches and which otherwise
  stops the program with that message. A `malloc` the program declares
  and calls itself still returns NULL, as C's does, and ends a library
  call when it next reaches a safe point or returns. The runtime's
  allocation test hook covers these allocations too. No measurable cost:
  a closure made and called per step 577 against 551 ms, a `ref` and a
  `heap.new` per step 880 against 873 ms, 20 million steps, Windows MinGW
  (#3377).
