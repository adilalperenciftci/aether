- **Shell tests ask `uname -s` for the platform, never the environment's
  `OS`.** `std_ipc_bash_chain` and `std_ipc_roundtrip` skipped on Windows only
  when `OS` was `Windows_NT`. An MSYS2 login shell started from Git Bash does
  not carry that variable, so a sweep run from it took their POSIX path on
  Windows and failed with "unsupported on Windows". They case on `uname -s`
  now, and `check_platform_env.py` also rejects a shell script that reads
  `$OS` without setting it. CONTRIBUTING.md's portability advice, which
  recommended `os_getenv("OS") == "Windows_NT"`, recommends `os.platform()`
  and `uname -s` (#3160).
