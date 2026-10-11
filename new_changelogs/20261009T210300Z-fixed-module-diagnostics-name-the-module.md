- **Unreachable code, a duplicate match arm, an escaping `@scoped` binding,
  an `Isolated[T]` value used twice and an effect-tag violation in an
  imported module name the module.** They named the importing file with the
  module's line number (`main.ae:9:5` for `lib/unr/module.ae:9:5`), so the
  snippet was a line of the wrong file or none at all. They now carry the
  file of the definition they are in, as the type checker's other
  diagnostics and the unused-variable warning already did (#1946, #2064).
