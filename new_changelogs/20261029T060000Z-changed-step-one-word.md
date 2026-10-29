- **A plain actor step reads one word to know it has nothing to put
  aside.** The step barrier looked at each part of the context it puts
  aside (spawn claims, execution accounts, sandbox levels) behind a load of
  its own, at both ends of every step, which cost send-heavy actors about 3%
  (ping_pong 11.96 against 11.65 M msg/s). The parts' globals are now bits
  of one word, `aether_caps_slow`'s step bits (the restart claims and spawn
  captures are counted there too), read once at each end with one predicted
  branch, and the parts are looked at out of line only when it is set:
  ping_pong is at 11.87, thread_ring, fork_join, counting and skynet are
  where they were before the step-context rule.
