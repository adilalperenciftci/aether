- **Tests ask the build which platform they run on.** Eleven tests decided
  they ran on Windows from `getenv("OS") == "Windows_NT"`, a variable
  cmd.exe and the desktop set, so from a shell without it (an MSYS2 login
  shell with a clean environment, a CI step, a service) a Windows build
  took the POSIX branch and failed. They ask `os.platform()`, and
  `make check-tests` fails on a `getenv("OS")` in tests, std or contrib
  (#3119).
