- **A handler answers its own ask whatever it does first.** The ask a
  handler holds is its thread's step context, and a send to an idle actor of
  the same core steps that actor inline, there and then: the inner step left
  its own context in place, so a handler that sent before it replied
  replied to no one, and its asker waited out the 5 s timeout. Every step
  (on a core, inline, on an actor's own thread, on the cooperative
  scheduler) now starts with no ask in hand and gives the enclosing step its
  context back. An ask its handler leaves unanswered fails when the step
  ends, as `"the handler returned without replying"`, instead of at the
  timeout, and its slot is freed (#3205).
