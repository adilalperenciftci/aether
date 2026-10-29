- **The cooperative scheduler never steps an actor inside its own
  handler.** An ask polls every actor until its reply, and the poll stepped
  the asking actor too: its next message was handled inside the handler
  that asked, its state changing under it, and a `stop()` or a panic there
  finalized the actor (its Down sent, its queue dropped) while the first
  handler still ran. An actor whose step is on the stack is now left alone,
  as threads leave an actor stepping: its next message waits for the
  handler to return (#3391).
