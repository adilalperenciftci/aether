- **A panic out of a link's end no longer stops the thread's later links
  (#3400, a follow-up to #3394).** Ending an actor drops the messages
  that wait for it, and a dropped message's release runs the drop
  function of an owned field (#3142), which is the program's code and may
  panic. Where a death is finalized as soon as it is seen (the cooperative
  scheduler, the threaded one once stopped), such a panic jumped out of
  the queue that makes the ends links pass on and left the thread marked
  as making them: every later end a link passed on there was queued and
  never made. The queue is journaled with the unwind journal now, so a
  panic that leaves it puts it back empty; the ends it had not made yet
  are given up, as an unwinding recursion gave them up.
