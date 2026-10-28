- **A step nested in a supervisor's restart leaves the restart alone.** A
  send from a child's factory to an idle actor of the same core steps that
  actor inline, and the nested step took the supervisor's restart claim for
  its own: its panic undid the claim, so the supervisor gave up ("the
  restart of w failed") with an orphaned Worker made; its spawn of the
  child's type took the child's block, so the child's ref reached a Worker
  its factory never configured; and any spawn of it inside a factory
  (supervise.start in a handler) was taken for the child. Every step now
  puts the thread's claim, reborn block and spawn brackets aside at entry
  and gives them back at exit, and its panic undoes only what it made; the
  in-step flags the signal handler reads come back too, where an inner step
  had left them cleared for the rest of the outer handler (#3389).
