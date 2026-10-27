- **A receive arm `_ -> { ... }` runs.** The language reference documented
  the `_` arm as taking every message no other arm names, and it compiled,
  but codegen gave it no handler: such a message was dropped and the body
  never ran, and an actor whose only arm was `_` had none. The `_` arm now
  has a handler that every unnamed message type is dispatched to, the
  message is released after it as a handled one is, and an ask it does not
  answer fails at once. A second `_` arm in one actor can never run and is
  refused (E0600) (#3289).
