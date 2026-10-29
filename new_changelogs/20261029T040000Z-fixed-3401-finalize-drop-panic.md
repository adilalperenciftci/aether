- **A panic in a dropped message's release no longer stops an actor's end
  (#3401).** An actor's end drops the messages that wait for it, and a
  dropped message's release runs the drop function of an owned field
  (#3142), which is the program's code. Where a death is finalized as soon
  as it is seen (the cooperative scheduler, a stopped threaded one), a
  panic in it jumped out of the finalize: the messages after it were not
  released, and the actor's watchers and links were never told. Each such
  release runs in a frame of its own now, on every path that finalizes a
  death; a panic in it is reported through the death hook with the actor's
  id and the panic's reason, as the step barrier reports a panic in the
  release after a handler, and the drain and the notice go on.
