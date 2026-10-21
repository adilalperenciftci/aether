- **A parked core is woken for every message, and Windows no longer binds
  scheduler threads to one CPU.** Sends from a loop in `main()` (the batch
  path) and a core's deferred sends to another core enqueued without
  waking a core that had parked, and the park and the wake had no full
  fence between them, so either side could miss the other: a core slept on
  its messages until its timed wait ran out, at least a 15.6 ms tick on
  Windows. A fork-join of 8 workers ran from 1.05 to 21.81 M msg/s run to
  run; it runs at 24.83 to 31.89. On Windows a scheduler thread now gets an
  ideal processor, a hint, instead of a hard binding to one logical CPU,
  which it could not leave while another program's thread ran there
  (#3087).
