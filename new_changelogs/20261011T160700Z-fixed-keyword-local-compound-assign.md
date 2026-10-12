- **A local named after a C keyword works under a compound assignment, and
  beside a closure parameter of the same name.** Such a local is renamed for
  C (`short` becomes `ae_short`), but a compound assignment, which carries
  its target in the node itself, was left out: `short += 2` wrote a bare
  `short` and gcc failed. So was a closure parameter: beside a local
  `short`, `|short: int| -> short + 1` read its parameter as a capture of
  that local and declared `ae_short` twice (#2738).
