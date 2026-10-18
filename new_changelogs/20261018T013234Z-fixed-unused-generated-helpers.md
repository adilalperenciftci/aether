- **A program with closures, actors or owning structs no longer fails
  `-Wall -Werror` on helpers it does not call.** Every closure env's
  `_free`, every actor's handler-table init, every owning struct's
  `_aether_<op>_<S>` helpers, and `rdtsc` and the reply-buffer releases are
  `static`. When the program did not call them, each was
  `-Wunused-function` under `-Wall` on gcc and clang. They now carry
  `AETHER_MAYBE_UNUSED`, as the imported wrappers already did. A main with
  actors and no `return` wrote a `main_exit:` label that nothing jumped to
  (`-Wunused-label`); the label is now written only when a goto targets it.
