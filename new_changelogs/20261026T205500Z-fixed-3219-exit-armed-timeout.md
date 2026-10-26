- **The end of `main` no longer waits for an armed receive timeout.** An
  actor with `after 60000` that handled a message just before `main` returned
  held the exit for that minute and then ran its timeout. The end of `main`
  now waits for the messages sent to be handled and not for countdowns, on
  both schedulers; `wait_for_idle()` still waits for them, so a program that
  wants a countdown to fire calls it first. The cooperative scheduler counted
  every check of an armed countdown as work, so its `wait_for_idle()` and its
  end of `main` spun on the CPU until the deadline; it now counts only a
  countdown that fires, and `wait_for_idle()` sleeps while one runs (#3219).
