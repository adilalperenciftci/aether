- **On Windows a runtime lock allocates nothing once it is made.** A
  critical section took a 48-byte debug record from the heap the first time
  a thread waited on it, at an arbitrary later point. heap_in_use counts
  every block on Windows, so an exact leak check (`std.mem.steady_growth`)
  read it as growth, and a program that spawned and released actors failed
  it now and then. The runtime's mutexes are made without the record, which
  only served a debugger's lock listing. The Windows process table in
  `std.os` is a statically initialized SRW lock now: it was made on first
  use behind an unguarded flag, so two threads spawning at once could both
  initialize it (#3346).
