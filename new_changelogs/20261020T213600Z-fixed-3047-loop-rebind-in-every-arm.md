- **E0902's check of a loop's next pass takes a local bound anew in every
  arm.** A loop body's if/else, or a `match` whose arms cover its subject,
  that binds a local whole in every arm before reading it leaves the local
  holding, in that pass, only what the pass binds, as a statement of the
  body binding it does: `kept = q` after it no longer counts the `p` the
  pass before stored (#3047).
