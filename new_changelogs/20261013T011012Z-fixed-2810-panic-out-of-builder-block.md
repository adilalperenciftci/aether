- **A panic out of a builder block, or after a string went into a map, no
  longer corrupts the heap when a `try` catches it.** Two faults met in
  `try { run("x") { set_opt("k", "v")  boom(1) } } catch e { }`, which
  crashed with heap corruption within a few hundred catches. The panic
  leaves the block by longjmp, skipping the block's context pop and the
  config release of #2791: every caught panic left an entry on the builder
  context stack, and after 64 of them a block's setters filled the config
  of a call a panic had abandoned. The catch now puts the stack back to its
  depth at the `try` and releases the configs of the blocks the panic
  abandoned. And a string a setter passed on to `map.put` (or `list.add`)
  was adopted by the container while still in the panic journal its first
  owner kept it in, so the panic's drain freed it under the container and
  freeing the container freed it again; a plain map filled in a `try` body
  crashed the same way. A container that adopts a string now takes it out
  of the journal (#2810).
