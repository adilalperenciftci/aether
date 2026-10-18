- **A constant a glob import brings in can be written bare.** After
  `import std.fs (*)`, a bare `KIND_NO_SPACE` type-checked (the glob binds
  each of the module's names) but nothing renamed it to the module's
  constant, so the C named an undeclared identifier. The program's bare
  references to a glob-imported constant are now renamed as a selected
  one's are; a local of that name stays the local, and a name the program
  defines itself is the program's.
