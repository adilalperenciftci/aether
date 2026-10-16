- **A string an `--emit=lib` export returns is the caller's, and goes back to
  the library's runtime.** The alias handed out the characters of a counted
  string that nothing ever released, so every call leaked it, in a C host and
  in a program importing the library as a binary (#2931). `aether_<name>()`
  now returns the string's handle, `const void*`: read it with
  `aether_string_data()` / `aether_string_length()` and give it back through
  `aether_<lib>_string_release()`, which the library exports and its catalog
  names (schema 1.9, `string_release`; `ae lib-info` prints
  `String release:`). `<lib>` is the library's package, else its entry file's
  stem (a `--namespace` library's own name). A binary import copies the string into the program's runtime and
  gives the library's back, and the bindings `ae build --namespace` generates
  do the same for Python, Ruby and Java. **Breaking** for a C, Swift or other
  host that reads an export's string result as `const char*`:

  ```c
  /* before */
  const char* s = aether_greet("world");
  puts(s);

  /* after */
  const void* s = aether_greet("world");
  printf("%.*s\n", (int)aether_string_length(s), aether_string_data(s));
  aether_greet_string_release(s);
  ```
