- **A local named after a C keyword works under a compound assignment and
  as a closure parameter.** Such a local is renamed for C (`short` becomes
  `ae_short`), but a compound assignment, which carries its target in the
  node itself, and a closure parameter were left out: `short += 2` wrote a
  bare `short` and gcc failed, and `|short: int| -> short + 1` redeclared
  `ae_short` as another kind of symbol (#2738).
