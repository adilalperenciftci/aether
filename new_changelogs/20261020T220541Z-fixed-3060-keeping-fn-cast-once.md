- **A keeping function cast to a C function pointer is one error, wherever
  it is written.** `keep_it as fn(ptr, ptr)`, with `keep_it` keeping a
  `@keep ptr` parameter, was E0902 twice as a struct literal's field and
  three times as an if-expression's arm, and not at all as an array
  literal's element or a match arm's value, which compiled. Each such cast
  is now refused once; a cast that names a mode itself, `as fn(@keep ptr)`,
  is refused for that alone (#3060).
