- **`ae <command> --help` prints the command's options and does nothing
  else.** Inside a project `ae build --help` built the project: the build
  skipped the flag as consumed by an earlier parse that had never acted on
  it. Most commands had the same fault in some form: `run`, `check`,
  `inspect`, `test` and `examples` ran or built, `install` and `upgrade` went
  to the network, `repl` started, `use` and `lib-info` took `--help` for a
  name, and `init`, `add`, `cache` and `bindgen` printed their usage as an
  error. `-h` and `--help` are now answered before any command runs, for
  every command, with its usage on stdout and exit code 0; after `--`, as in
  `ae run app.ae -- --help`, they still go to the program. `ae help` lists
  `lib-info` too (#2753).
