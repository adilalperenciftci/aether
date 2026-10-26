- **Every spawner reports a program that cannot start as an error.**
  `spawn_sandboxed` and contrib's Go and Aether process hosts returned 127
  for a program that is not there or cannot be executed, which a program
  that ran can return too; they return -1 now, learnt through a
  close-on-exec error pipe as std.os does (#3170). The Aether host also
  keeps a captured stdout when the parent had stdout closed: its pipe was
  then already fd 1, and the close after a `dup2` onto itself closed it
  (#3210).
