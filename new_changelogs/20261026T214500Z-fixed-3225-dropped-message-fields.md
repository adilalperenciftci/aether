- **A message dropped instead of handled releases what its fields own.** Its
  payload struct was freed and its strings, closures and structs were not:
  the messages queued to an actor that panicked or was released, the ones
  sent to it after, and one the scheduler refused. A message of a type its
  receiver has no handler for, and the one a handler panicked on, leaked
  their payload too. Each program now emits one `_aether_release_message`,
  every spawn stores it in the actor's `release_message`, and every drop goes
  through `aether_message_drop()`; the step records the message its handler
  is running on, so the panic barrier drops it (#3225, step 1 of #3142).
