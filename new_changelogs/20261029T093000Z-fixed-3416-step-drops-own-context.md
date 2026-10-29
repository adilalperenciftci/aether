- **A receiver stepped inline runs its drops in its own context again.**
  Since #3403 the step gave the enclosing context back before it dropped
  the message a panicking handler ran on, and before it finalized an actor
  its step ended, whose queued messages' drops are the receiver's code. An
  actor stepped inline (a send or an ask of an idle actor of the same core,
  a cooperative ask's poll) then ran those drops in the sender's context: a
  drop inside a deny-all enforce block read PATH as refused, where on the
  actor's own thread it reads it, a drop inside a library call was cut by
  the call's deadline, and its allocations were charged to the call's
  account. The drops, the finalize and the death hook now run in the step's
  context, each in a containment frame, and the context is given back
  after them (#3416).
