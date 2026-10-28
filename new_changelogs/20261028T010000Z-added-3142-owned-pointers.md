- **Owned pointers: a buffer released wherever it ends up.** `type Buf =
  owned ptr drop bytes.free` makes a pointer type whose holder releases it
  with the named function: a local at its function's every exit and when it
  is bound again, a handler's binding of a message field when the handler
  ends, an actor's state field when it is replaced or the actor ends, and a
  message dropped undelivered with the message. `move` hands it on and
  leaves the place it left holding nothing, a function borrows it as it
  borrows a `ptr`, and a copy without `move`, a free or keep behind the
  holder's back, and a holder that could not release it (a struct field, a
  closure, an optional) are E0905. A buffer moved to an actor no longer
  leaks when the handler forgets it or its actor dies first (#3142).
