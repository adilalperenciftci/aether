- **`ae check` warns on a call that names its module twice.** W1006:
  `json.json_free(v)` where `json.free(v)` is the same function, with a hint
  to write the short form or run `ae fmt --short-names <file>`, which
  rewrites every such call. The tree was rewritten to the short form; the
  warning keeps the long one from coming back. Only where the compiler
  resolves both spellings to one declaration (a module exports one name per
  operation, E0305); a long name with no short form (`sha3.sha3_256_hex`)
  is not reported, nor is a call inside an imported module, and `ae build`
  does not report it (#2976).
