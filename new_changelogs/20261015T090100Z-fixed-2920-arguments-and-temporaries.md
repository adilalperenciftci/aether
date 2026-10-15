- **Arguments and temporaries outlive what uses them.** A string read from
  a module `var` or a field and passed to a function is held by the caller
  for the call, so a store into that place inside the call no longer frees
  the argument. A fresh string passed to a call that returns a view of it
  (`string.bytes(make())`) lives to the end of its statement, as a
  temporary does in C++; it was freed as the call returned, and the view
  read freed memory (std.cryptography's argon2 hashed garbage). A field
  read ahead of a call holds a reference of its own (#2920).
