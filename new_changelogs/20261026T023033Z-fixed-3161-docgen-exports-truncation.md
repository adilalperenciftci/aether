- **docs/api documents std.http, std.file, std.pqueue and std.set again.**
  docgen took the first "exports" in a module.ae, comments included, and the
  next `(` as the export list, so std.http's page listed `this` and
  `module` (from "re-exports ... (this module)") instead of its 133
  exports, and the other three a single word each. The export list is now
  the `exports (` that starts a code line. docgen also cut every string to
  a fixed buffer without a word (names, signatures, doc blocks, the module
  header, lines, the export table) and documented `const SEP = "/"` as `"`;
  every string now grows to fit, and a module it cannot read or an export
  list that never closes fails the run (#3161).
