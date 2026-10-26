- **`ae help` reports a compile error that has no code.** Only
  `error[Eabcd]` lines became findings, so an unresolved import, often a
  script's only error, was dropped and the run said "no diagnostics" about a
  file that does not compile. An uncoded `error:` line is a finding now, at
  the line its `-->` gives; an unresolved import names the directories the
  compile searched and how to add one. A compile that fails with nothing
  ae help can explain says the file does not compile, shows what the
  compiler printed, and exits 1, and `--json` carries `"compiled"` (#3184).
