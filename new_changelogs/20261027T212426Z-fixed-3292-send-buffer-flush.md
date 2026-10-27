- **The C send buffer sends every message it holds, in order.**
  `send_buffered()` stored a message one past its buffer when a flush could
  place nothing (the target on the sender's core, its mailbox full), and
  wrote further with each send after. The flush itself kept what its
  same-core path could not place (and a target change then sent those to the
  new target, a force flush dropped them), dropped the part of a cross-core
  batch a full queue had no room for while still counting it in flight, so
  the actor could never move again, counted none of its messages as sent, and
  from a thread that is no core's wrote the shared channel without its lock.
  A flush now hands the messages to a new `scheduler_send_many()`, which sends
  them as that many single sends would go (behind what is queued for the
  actor, kept when a queue is full) and enqueues a cross-core run in one
  batch. The per-actor SPSC queue the same-core path used, outside every
  ordering rule and drained only while the mailbox held something, is filled
  by nothing now (#3292).
