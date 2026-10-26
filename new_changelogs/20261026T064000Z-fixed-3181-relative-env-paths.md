- **A relative `AETHER_CACHE_DIR` or `AETHER_LIB_DIR` keeps meaning a
  directory where the command was typed.** Once `ae run`, `ae build` or
  `ae check` entered a project to compile from its root (#3181), a
  relative `AETHER_CACHE_DIR` became a cache inside the project, and a
  relative `AETHER_LIB_DIR` searched the project's directories instead of
  the ones named. Their relative entries are re-based onto the directory
  the command was typed in when it enters the project, as `--lib`, `-o` and
  `--extra` are.
