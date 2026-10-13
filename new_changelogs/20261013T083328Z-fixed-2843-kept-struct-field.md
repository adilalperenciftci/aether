- **A struct's string field handed to a function that keeps it stays
  alive.** A function that stores its `string` parameter where nothing
  releases it (a module-level `var`, say) keeps the pointer it was given;
  a local handed to one is not freed at its scope exit, but a struct field
  was freed by the struct's destructor, at once for a struct a call
  returned: `n = string.length(keep(make_item(w).name))` left the kept
  string pointing at freed memory. The field now gives its reference up at
  the call, as it does to a function that frees it (#2843).
