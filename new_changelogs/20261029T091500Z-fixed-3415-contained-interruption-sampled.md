- **An ordinary panic during an interruption's unwind no longer ends the
  interruption.** A containment frame (`aether_contain`, which runs an
  ending actor's message drops) told the call's interruption from a panic by
  whether an interruption was marked once it had caught one. When the drop
  ran while the interruption was already unwinding the call (a `defer` the
  unwind ran killed an actor, which the cooperative runtime finalizes there
  and then) and panicked, the drop's panic was taken for the interruption,
  which was taken off its way: a `try` the unwind reached ran its handler,
  and a call with none ended `AETHER_PANICKED` instead of `AETHER_DEADLINE`.
  The frame now puts an interruption on its way aside while its code runs,
  and tells what it caught by what the code raised (#3415).
