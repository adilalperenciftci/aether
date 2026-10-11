- **UFCS on a selectively imported function compiles.** With
  `import m (f)`, `x.f(args)` on a local was rewritten to the bare `f(x, args)`
  after the pass that renames a selectively imported call to its qualified
  `m.f`, so codegen emitted a call to an undeclared C function `f` (a compile
  error) instead of `m_f`. The UFCS rewrite now applies the same import-alias
  lookup. Found through aether-ui, whose DSL is imported selectively and whose
  modifiers chain (`g.datagrid_on_select() callback { ... }`).
  tests/integration/ufcs_selective_import.
