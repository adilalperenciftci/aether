- **An ended actor can be restarted in place, under the same ref.**
  `actors.rebirth_begin(child)` claims an ended child once its death is
  finalized and no message of it is in flight (0 means "not yet, try again";
  -1 that it cannot be), the child's factory then runs, and its spawn of the
  child's actor type takes the child's own block: the old state destroyed,
  the fields zeroed, the state initializers run, `incarnation` one more, and
  the child alive again when the generated spawn's new last line
  (`scheduler_spawn_ready`) runs. `actors.rebirth_end(child)` says whether it
  is, or undoes an unfinished restart. Messages queued at the death and sends
  while the child is dead are dropped once and counted; sends after the
  spawn reach the new incarnation, and a ref held by a client keeps working.
  `actors.incarnation(ref)` counts the restarts. This is what `std.supervise`
  restarts children with (#2974).
- **A panic while an actor's full mailbox was being made room in no longer
  strands messages.** The core went on putting the rest of a run of messages
  into the dead actor's mailbox, where nothing handled or credited them; it
  now drops them, counted with the death's (#2974).
