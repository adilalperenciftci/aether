- **Messages from one actor to another arrive in order while the target
  moves between cores, and a chain of actors gathers on one core.** When an
  actor moved to the core that sent to it, a message still queued on its old
  core was forwarded after it, and the sender's next message, sent to the
  new core directly, could be stepped first. A test with eight senders and
  four moving targets saw 14,400 to 21,924 of 3,200,000 messages out of
  order (#3093). A message re-queued because the target's mailbox was full
  went to the back of a queue and could be overtaken the same way.

  Now every message routed through a core's queues is counted on its target
  until it reaches the mailbox, and an actor moves only by its own core with
  none in flight. A full mailbox is made room in by stepping the actor, so
  the message keeps its place.

  A moved actor used to take the place its sender had just left, so a thread
  ring only shifted around the cores. Now it moves before it runs the
  message, so the ring gathers on one core in its first lap: 24.91 M msg/s
  from 3.03, on 1/71 of the CPU time (#3090). A worker's batch is delivered
  as one run: fork-join 39.69 M msg/s from 30.23. Ping-pong and counting are
  unchanged.
