- **`middleware.rewrite_new()` and `middleware.error_pages_new()`.**
  `use_rewrite` and `use_error_pages` take opts that only the C bindings
  made, and the module exported neither: every program declared the extern
  itself (#3218).
