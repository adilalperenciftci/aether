- **Leaving a builder's trailing block early releases the builder's
  config.** A builder call makes its config with the builder's factory, runs
  the block against it and hands it to the builder, which owns it from then
  on. A `return` in the block, with a value or without, or a `break` or
  `continue` out of it, left before the builder ran, and nothing released
  the config: every such call leaked it (a `map_new` config with one option
  set, 260 bytes a call). Any way out of the block but its natural end now
  releases it, with `map_free` for the default `map_new` and with
  `<stem>_free` for a `<stem>_new` factory the program defines or declares
  (`list_new`, `list_free`); a nested builder call's block releases both
  calls' configs. A factory without such a release still leaves its config
  to the builder's protocol. A builder whose body never names `_builder`,
  which therefore never frees, keeps or returns its config, now releases it
  on entry the same way; every call of one made with a block leaked the
  config before (#2791).
