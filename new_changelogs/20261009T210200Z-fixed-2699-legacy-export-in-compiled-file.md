- **A legacy `export f()` in the file being compiled is checked and built as
  a plain definition.** The wrapper stayed in that file's tree and most
  passes did not look through it. The type checker's third pass skipped an
  exported function, so an unused local (W1001), code after a `return`
  (W1002), an escaping `@scoped` binding and an `Isolated[T]` value used
  twice went unreported. A result type left to inference was never inferred,
  a function defined after its caller had no C prototype, an `@pure` caller
  did not see what an exported callee reached, a name taken from libaether
  (`string_concat`) was not renamed and the link failed, an exported clause
  left its set (`fact(5)` printed 0), an exported constant was undeclared in
  the C and an exported actor could not be spawned. The compiler now puts
  the declaration in the wrapper's place right after parsing; what an
  importer may name is read from the module's own parse and does not change
  (#2699).
