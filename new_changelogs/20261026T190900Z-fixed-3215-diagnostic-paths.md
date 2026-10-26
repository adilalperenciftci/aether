- **A diagnostic names its file from where the command was typed.** When
  `ae build`, `ae run` or `ae check` compile from a project root they
  entered (a walk-up to aether.toml, or a project named on the command
  line), every error, warning and `ae help` hint named the file from that
  root: `sub/bad.ae` for the bad.ae typed in sub/, which no terminal or
  editor could open from there (#3215).
