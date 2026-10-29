- **A receiver stepped inside an enforce block runs without its grants.** A
  message an enforce block sends is handled with no grants, as an actor's
  thread handles it, but a send to an idle actor of the same core steps it
  inline, on the block's thread, and it ran with the block's levels: a
  deny-all block had the receiver's reads refused, or not, depending on
  whether the step happened inline. A step now puts the thread's levels
  aside (in every runtime copy that shares the count) and gives them back
  when it ends, so the receiver is checked the same whichever thread steps
  it, and the block's own code after the send is held to the block again
  (#3393).
