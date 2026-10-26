- **std.json and std.fs say what a string result is under the ownership
  model.** std.json's comments explained a "uniform-heap shape" for the
  retired heap classifier, and its code still built `string_concat("", "")`
  and `string_concat("not a string", "")` copies to satisfy it; a literal is
  now returned as a literal. std.fs's `read` and `read_binary` said the
  value "IS owned and must be freed", which a caller following the
  reference must not do: it is the caller's string, released like any
  other (#3168).
