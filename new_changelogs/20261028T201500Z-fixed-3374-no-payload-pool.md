- **Nothing claims a message payload pool any more.** The pool's acquire
  side was removed long ago (an actor can move to another core after a
  message is sent, so a pooled payload would be released by a thread that
  does not own the pool), and every typed payload is a heap copy. Yet
  `AETHER_FLAG_LOCKFREE_POOLS` was documented as a working option and
  reported enabled, the `AETHER_VERBOSE` print listed "[ON] TLS Message
  Pools", five docs presented the pool as running, every actor program
  asked `aether_message_pool_stats` for counters nothing incremented, and
  every `aether_free_message` first asked the pool whether it owned the
  payload, which it never did. The pool code is gone and
  `aether_free_message` is a `free()` (8.20 ns against 8.27 ns a free on
  Windows MinGW). `AETHER_FLAG_LOCKFREE_POOLS` stays
  defined, accepted and ignored, and is deprecated:
  `aether_runtime_has_feature()` reports it off and `use_lockfree_pools`
  in the runtime configuration is always 0 (kept, so the fields after it
  keep their offsets). `aether_message_pool_stats` stays, deprecated,
  reporting zeros, and generated programs no longer call it (#3374).
