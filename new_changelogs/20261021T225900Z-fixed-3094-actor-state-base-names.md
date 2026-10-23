- **An actor state can be named like any of the runtime's actor fields.**
  `state id`, `state active` or `state mailbox` passed the checker and then
  failed in the C compiler with a duplicate member, because the generated
  actor struct spliced the runtime's actor fields in beside the states. The
  base is a member of its own now (`ActorBase _aether_base`), so those
  names are ordinary states. Only a state named `_aether_base` itself is
  refused, by the checker with a message (#3094).
