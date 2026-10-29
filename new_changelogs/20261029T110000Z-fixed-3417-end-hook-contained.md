- **An actor's end goes on past a death hook that panics.** The drop of a
  message an ending actor leaves undelivered runs in a frame of its own
  (#3401), and a panic in it is reported to the death hook, which ran bare
  there. A hook that panicked then left the finalize halfway: the messages
  it had drained were never counted, so `scheduler_shutdown` and
  `wait_for_idle()` waited for them forever, its links and watchers were
  never told, and the finalize, marked done, never ran again. The hook now
  runs in a frame of its own, as the step barrier's does: its panic is
  reported on stderr and the end goes on (#3417).
