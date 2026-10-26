- **A spawned child's stdio is wired right whatever the parent has closed
  of 0, 1 and 2.** On POSIX the pipes and the file a spawn made could take
  those slots, and the child's own wiring then overwrote or closed them:
  `os.spawn_proc_to` lost all output when the parent's stdin was closed,
  and `os.run_full` lost the child's stdout or stderr when the parent's was.
  The child now moves every descriptor it installs off 0 to 3 before the
  first install (#3199).
