- **A program that reads the environment or a file keeps its actor steps
  plain.** The step barrier's sandbox bit was set by the first sandbox
  check of any kind, a getenv or a file read with no enforce block
  anywhere, so most programs paid the barrier's slow look at every step.
  The bit is now set only when a sandbox level may be in force where the
  copy's steps can see it: when the first thread enters a level counted by
  this copy, or when the copy shares another copy's count. An actor of a
  library with its own runtime, stepped inside an enforce block of another
  copy, now runs without that block's levels even when the library had
  made no sandbox check before (#3419).
