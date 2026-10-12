- **`ae test a.ae b.ae` runs both files.** Every argument that was not a flag
  was assigned to one target and only that one was collected, so the second
  file was dropped without a word and a failing test in it passed the run.
  Every file and directory named now runs, in the order given, and the run
  fails if any test in any of them fails. A target that is neither a file nor
  a directory is an error naming it; it used to fall back to running
  `tests/`, so a mistyped name ran something else and could pass (#2752).
