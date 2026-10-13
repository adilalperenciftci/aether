- **A builder call with a trailing block is stored, passed and thrown away
  as any call is.** Its statement forms assigned `s = label(args, cfg)` by
  hand after the block, so a string it returned was never tracked (bound to
  a local, replaced, or thrown away, it leaked, #2866), a fresh string passed
  to it was never freed (#2853), a string field passed to one that frees or
  keeps its parameter was not handed over (#2851), and stored into a struct
  field it ran with its block dropped (#2855). The block and the arguments
  now run ahead of the statement, which is then emitted as for any value,
  the call made with the filled config.
