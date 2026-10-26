- **A project's imports resolve the same from any directory.** `ae run
  app/` and `ae build app/` pointed the source into app/ but compiled from
  the caller's directory, so a module in app/lib was "unresolved import
  'greet': no module of that name was found in src/, the project root, and
  installed packages", a message naming no directory. `ae run` and `ae
  check` from app/src failed the same way, while `ae build` from there
  worked. Each now compiles from the project root, as `ae build` already did
  from a subdirectory, with the paths typed relative to where the user
  stands (`--extra`, `-o`, and now `--lib` too) re-based; `ae run` still
  starts the program in the directory the command was typed in. A missing
  module's error lists every directory searched, in order, in full. The
  entry program's imports no longer sometimes look beside the file first: the
  flag choosing that order started as whatever `malloc` returned (#3181).
