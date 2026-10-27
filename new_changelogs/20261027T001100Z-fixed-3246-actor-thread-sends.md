- **An actor with a thread of its own sends as a foreign thread.** It ran
  with its core's id, so its sends went straight into that core's mailboxes
  and into other cores' queues from that core, whose single producer is the
  core's own thread: messages were lost or delivered twice, and a sender
  could spin forever. It now sends through the locked foreign channel, and
  only a core's own scheduler thread steps for an ask or relieves its core
  (#3246).
