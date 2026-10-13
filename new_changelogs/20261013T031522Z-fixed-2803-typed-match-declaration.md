- **`int r = match o { ... }` binds the match's value.** The `T name =
  expr` declaration parsed its initialiser as an expression, which does
  not include `match`, so the declaration had no initialiser and the match
  ran as a statement of its own: `r` was read uninitialised. It parses the
  match as `let r: int = match ...` does (#2803).
