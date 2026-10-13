- **An `fn[N]` local releases its closures.** A local array built from
  capturing closure literals held the one reference to each environment and
  never released them, so each call of a function holding one leaked them
  all. Its scope exit now releases them, as a closure local's does; a struct
  given the array takes references of its own (#2868).
