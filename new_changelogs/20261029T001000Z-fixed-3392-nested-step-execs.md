- **An actor stepped inside a library call runs outside it.** On the
  cooperative runtime (wasm, ESP32) an export's ask polls the actors, so the
  asked actor runs on the call's thread, inside the call; on threads a
  send's inline step can run one inside a call too. The call's deadline was
  then raised in the actor's loop and caught by the actor's barrier: the
  actor died ("the call's deadline passed") and the interruption stayed
  marked, so the next call's `try` could not catch an ordinary panic and the
  call ended with the stale outcome (#3392). The actor also read the caller
  info the host had set for the call (#3396). A step now puts the thread's
  calls aside, with their deadline, cancel, noted stop, interruption and
  caller info, and gives them back when it ends: the actor runs as on a
  core's thread, and the call is cut at its own next safe point after.
