- **A string stored into a module-level `ptr` var builds without a C
  warning.** `gp = s` or `gp = string.concat(...)`, with `gp` a `ptr`
  global, assigned a `const char*` to the `void*` static, and gcc warned
  (discards 'const' qualifier) in the user's build, an error under
  `-Werror`. The store casts to the global's type (#2811).
