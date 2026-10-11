- **An `extern` of a libc function such as `signal` compiles.** The code
  generator does not emit its own declaration for a libc name (the system
  header's prototype is the canonical one), but only `stdio.h`, `stdlib.h`,
  `string.h` and `time.h` were in the generated C, so `extern signal(...)`,
  `raise`, `getpid`, `isatty` and the other names declared elsewhere had no
  declaration at all, which gcc 14 rejects. The header of each such name a
  program declares (`signal.h`, `unistd.h`, `sys/wait.h`, `sys/stat.h`,
  `fcntl.h`, `sys/time.h`, `strings.h`) is now included, guarded so a
  header a platform lacks is skipped (#2676).
