- **A scheduler park longer than 2.1 seconds now waits as long as it was
  set to on Windows.** The deadline of a park's timed wait was computed in
  a `long`, which is 32 bits on Windows and on 32-bit targets, so a wait
  past 2147 ms (only the test settings `scheduler_set_actor_park_ms` and
  `scheduler_set_core_park_ms` ask for one) returned at once or slept for
  weeks. The default parks, 1 to 32 ms, were not affected (#3095).
