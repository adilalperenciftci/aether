- **An unused string literal no longer breaks a `-Wall -Werror` build.**
  Since 0.818 every string literal of the program got a static pinned
  AetherString, `_ae_slit_<i>`, even one every use of which reaches the C as
  plain characters (`println("x")` is `puts("x")`). The unused `static const`
  is `-Wunused-const-variable`, which `-Wall` turns on for C on gcc and
  clang, so `main() { println("Usage:") }` failed to compile under
  `-Werror` (found by fight-flash-fraud-port's bump to 0.823). The statics
  are now written once the program is, for the literals the C names: the
  pinned string, or only its bytes where that is all it reads. A program
  that uses all of its literals' statics gets the same C as before.
