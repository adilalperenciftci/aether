- **An ask on the cooperative runtime honours its timeout.** With no
  threads (Emscripten, esp32, a `-DAETHER_NO_THREADING` build) an ask ignored
  `timeout_ms`: a handler slower than the timeout still had its reply taken,
  and an ask behind more than 100 000 queued messages ended "timed out" long
  before its timeout, its polls counted instead of timed. The polls now stop
  at the deadline and only there, and a reply that comes after it is
  discarded as late, so the ask ends with "ask timed out after N ms", as it
  does with threads. An ask that ended with its message still queued left
  the message pointing at the asker's stack, and its handler later wrote its
  reply there: the next ask from the same place received that reply (a
  crash when the types differ). The message now forgets the asker when the
  ask ends, and is handled as a plain send. The ask failure reasons test runs
  on the cooperative runtime in CI (#3330).
