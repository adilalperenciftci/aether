- **`*mod.T` is a type, and a qualified type names a module that has it.**
  `mod.T` parsed in a type position, but its pointer form `*mod.T` stopped
  at the `.` ("Expected LEFT_BRACE, got DOT"), so `f() -> *gpu.GpuShader`
  needed a selective `import gpu (GpuShader)` and `*GpuShader`. It now parses
  in a return type, a parameter, a struct field, an `as` cast and a typed
  declaration, as the struct the selective import would bring in. The
  qualifier was also dropped unchecked: `gpu.Missing` reached the C compiler
  as an unknown type name. It is now an error at the source line, `module
  'gpu' has no type 'Missing'`, and so are a qualifier naming no imported
  module and a type the module does not export. `ae fmt` no longer writes a
  line-leading `*Node n = ...` as `* Node n = ...`.
