- **`AETHER_MSG_POOL_SIZE` and `AETHER_PROFILE` are gone; setting them
  never had an effect.** The two environment variables were documented as
  the message pool's size and a memory profile (`micro`, `small`, `medium`,
  `large`), but the only code that read the size they set was
  `runtime/actors/aether_message_pool.h`, a header nothing included, whose
  pool variable was defined nowhere. They changed one line of the
  `AETHER_VERBOSE` configuration print and nothing else, so a program that
  sets them is unaffected. The header, its section in
  `docs/runtime-config.md`, the two rows of the environment table, the
  `msg_pool_size` and `profile` fields of the runtime configuration and the
  profile helpers are removed (#3373). The compile-time `-DAETHER_PROFILE`
  switch of the profiler is unrelated and unchanged.
