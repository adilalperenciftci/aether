- **An actor with a thread of its own that panics gives up its inbox.** Its
  thread left at the death and the messages still waiting in its inbox were
  never dropped or credited, so `scheduler_wait()`, and with it the
  shutdown, waited for them forever. The death is now finalized on that
  thread at the end of its loop, the inbox with the mailbox, and a sender
  that pushes after that drain drops what it pushed (#3298).
