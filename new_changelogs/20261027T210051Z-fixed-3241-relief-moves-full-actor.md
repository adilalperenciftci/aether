- **A core waiting in an ask hands over an actor with more messages than its
  mailbox holds.** Such an actor kept one of its messages in a core queue,
  and moved, its senders' next messages could have overtaken it, so it waited
  for the ask to end. The relief now puts what its full mailbox cannot take,
  in order, into an overflow that belongs to the actor (its `inbox`, as an
  actor with a thread of its own has), and the actor moves with mailbox and
  overflow together. Every delivery to an actor whose overflow holds anything
  goes behind it (the core loop's batch, local sends, the reliefs, the
  deferred-send flush), each step refills the mailbox from it, and a panic
  drops what it holds, so each sender's messages keep their order on any
  core (#3241).
