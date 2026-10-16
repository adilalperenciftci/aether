- **A string reaches every C extern as its characters.** An argument in
  a C-variadic extern's `...` (`printf(fmt, s)`) was passed as it is held,
  so a string built at run time formatted its AetherString header (#2914).
  An extern bound to another symbol (`@extern("sym") name(...)`) had its
  parameters looked up by that symbol, which the extern table does not
  file entries under, so none of its `string` arguments were unwrapped;
  std.strbuilder's `append_format` formatted a counted format string's
  header (#2915). A call finds its extern by the Aether name now, and a
  string in a vararg position is unwrapped as a declared `string`
  parameter is.
