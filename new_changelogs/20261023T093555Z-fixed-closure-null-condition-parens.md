- **`if c == null` on a closure builds without a clang warning.** Since
  0.837.0 a closure compared with `null` asks whether it holds a function
  (#3062), written `((c).fn == 0)`; as an `if` or `while` condition that
  became `if (((c).fn == 0))`, which clang's default
  `-Wparentheses-equality` warns about, so a program kept warning-free
  (ae3d's net module, built `-Werror` on clang) failed on it. The condition
  is `if ((c).fn == 0)` now, as every other `==` is; the comparison keeps
  its own parentheses where it is an operand (`&&`, `!`, a value).
