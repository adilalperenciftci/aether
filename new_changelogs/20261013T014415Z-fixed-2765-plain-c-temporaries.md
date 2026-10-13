- **The C a program gets for a compiler that is not GCC-compatible has no
  GNU statement expressions.** Every construct that needs a temporary in the
  middle of an expression wrote `({ ... })` whatever the C compiler, so on
  the path `AETHER_GCC_COMPAT 0` selects, which is what cl.exe compiles, 445
  of the 971 programs of the .ae sweep did not compile: storing a string into
  an array element, an argument freed after its call, an operand evaluated
  ahead to keep source order (which also used `__auto_type`), and the
  `!`, `??`, `?.`, `or` and string ownership forms among them. Each is now a
  comma expression whose temporaries are declared ahead of the statement it
  is in, the same C for every compiler; an evaluation-order temporary keeps
  `__auto_type` where the compiler has it and is declared with the
  operand's type where it does not. An `or` with a block handler, a `!` that
  propagates an error and a call whose trailing block runs where its value
  is used run as statements ahead of their statement when they are the
  first thing it evaluates (elsewhere they are still statement expressions,
  #2798). Every program of the sweep the compiler translates (975 of 977)
  now compiles as strict C11 with `AETHER_GCC_COMPAT 0` and runs right that
  way under gcc; under cl.exe 933 compile, the rest on other GCC-isms
  (#2799). `make test-msvc-compat` compiles a program per construct as
  strict C11 and under cl.exe, and runs them that way (#2765).
