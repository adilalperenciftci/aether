- **A `break` in a `switch` case leaves the switch, whatever its cases.** In
  a loop, a `switch` with a ranged case (`case 1..=5:`) is lowered to an
  if-chain, where the C `break` left the loop instead, and outside any loop
  it did not compile; a switch of plain cases left the switch but first ran
  the defers of the loop body around it, which then ran again when the body
  ended, and inside a `try` it popped the try's frame, which the try body
  popped again (the program aborted with "aether_try_pop on empty stack"). A
  `break` in an arm of a `match` on a sum type left the C switch that match
  lowers to, not the loop. A break now leaves the innermost loop or `switch`
  in every lowering, running the defers and popping the `try` frames of only
  what it leaves, so the code agrees with the missing-return check, which
  already read it that way (a function it accepted could fall off its end).
  Each case is a scope of its own: a `defer` written in a case ran at the end
  of the enclosing scope, even when the case never ran (#2696).
