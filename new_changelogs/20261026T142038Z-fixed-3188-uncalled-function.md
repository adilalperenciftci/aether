- **A function's name alone as a statement is an error.** It calls
  nothing: `serve { port(1) }`, a builder written without its `()`, read
  as the name and then a bare block, compiled without a word, and the
  builder never ran. The error is at the name, bare or qualified, and says
  to write `serve() { ... }` (#3188).
