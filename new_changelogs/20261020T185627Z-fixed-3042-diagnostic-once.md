- **A wrong lane name or an unknown bitstruct field is reported once.**
  `v.q` on an `f32x4` and `h.nope` on a bitstruct printed their E0200 two or
  three times, depending on where they stood, and in an `if` or `while`
  condition a "condition must be boolean" error followed. Each is reported
  once now, by the check of the member access, and a condition that
  reported its own error is not also called not boolean; the body of the
  `if`, `while` or `for` is still checked, so an error there is reported
  with it, and "For loop condition must be boolean" is at the condition
  rather than at 0:0 (#3042).
