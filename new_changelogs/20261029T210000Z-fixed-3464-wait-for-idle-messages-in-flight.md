- **`wait_for_idle()` no longer returns with messages in flight.** Its count
  of the messages still pending took sent less handled, and three things
  broke it. Each core's two counts were read in turn, so a message sent on a
  core already read and handled on one read after cancelled the reply it
  sent. The handled count went up by one for each step a core made, so a
  step that took no message (an actor killed mid-drain, or one another core
  had just taken) counted a message never handled, and the handled count
  passed the sent count for good, hiding as many pending messages from every
  later wait. And two batch paths counted their sends after the receiver
  could take them. Every core's handled count is now read before every sent
  count, a step counts only a message it took, and every send counts before
  its message can be taken: two actors trading messages on two cores (a
  stream's chunks and credits) no longer see the wait return mid-exchange
  (#3464).
