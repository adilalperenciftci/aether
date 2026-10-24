- **A spawned child keeps its parent's standard streams when the parent marked them close-on-exec.**
  Node marks its stdin, stdout and stderr close-on-exec, so a program run
  under Node that used `os.spawn_proc` (or the other fork-and-exec paths of
  `std.os`) started its child with none of the three, and a child that
  needs them failed in ways that named nothing: chromedriver spawned by the
  Selenium engine from Node could not start Chrome ("Failed to create Chrome
  process"), and the first file such a child opened took descriptor 0. The
  child now clears close-on-exec on 0, 1 and 2 before exec, which is what
  inheriting the parent's streams means; a stream the parent closed stays
  closed.
